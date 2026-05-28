// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "../BaseTest.sol";
import "./VaultHandler.t.sol";

/// @title InvariantTest - Production-grade stateful invariant suite for RebalancerVault

contract InvariantTest is BaseTest {
    VaultHandler public handler;

    uint256 private constant _DEAD_SHARES = 1_000;

    function setUp() public override {
        super.setUp();

        int24 correctedTick = (TICK_100K / TICK_SPACING) * TICK_SPACING; // 345200
        pool.setPrice(
            TickMath.getSqrtRatioAtTick(correctedTick),
            correctedTick
        );

        address pmAddr = address(vault.positionManager());

        vm.store(pmAddr, bytes32(uint256(0)), bytes32(uint256(1)));

        MockPositionManager(pmAddr).setMintReturn(1_000_000_000_000, 0, 0); // 1e12

        uint256 HUGE = type(uint128).max;
        token0.mint(pmAddr, HUGE);
        token1.mint(pmAddr, HUGE);
        token0.mint(address(vault.clSwapRouter()), HUGE);
        token1.mint(address(vault.clSwapRouter()), HUGE);

        token0.mint(owner, 1e10);
        token1.mint(owner, 1e28);

        (int24 lo, int24 hi) = _defaultRange();
        _initPosition(lo, hi, 1e7, 1e17);

        address[] memory actorList = new address[](5);
        actorList[0] = alice;
        actorList[1] = bob;
        actorList[2] = carol;
        actorList[3] = makeAddr("dave");
        actorList[4] = makeAddr("eve");

        handler = new VaultHandler(
            vault,
            pool,
            token0,
            token1,
            owner,
            operator,
            actorList
        );

        targetContract(address(handler));

        bytes4[] memory sels = new bytes4[](6);
        sels[0] = VaultHandler.deposit.selector;
        sels[1] = VaultHandler.depositToken1.selector;
        sels[2] = VaultHandler.redeem.selector;
        sels[3] = VaultHandler.rebalance.selector;
        sels[4] = VaultHandler.compoundFees.selector;
        sels[5] = VaultHandler.movePrice.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: sels}));
    }

    function invariant_A_shareConservation() public view {
        uint256 supply = vault.totalSupply();
        if (supply == 0) return;

        assertEq(
            supply,
            handler.sumActualBalances(),
            "INV-A: totalSupply != sum(balanceOf for actors + 0xdead)"
        );
    }

    function invariant_B_actorShareAccounting() public view {
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            address actor = handler.actors(i);
            assertEq(
                vault.balanceOf(actor),
                handler.ghostShares(actor),
                "INV-B: vault.balanceOf diverged from ghost - unexpected mint/burn"
            );
        }
    }

    function invariant_C_noFreeShareRoundTrip() public view {
        uint256 supply = vault.totalSupply();
        if (supply <= 1) return;

        uint256 ta = vault.totalAssets();
        if (ta == 0) return; // undefined share price, skip

        uint256[3] memory testShares = [
            uint256(1),
            supply / 2,
            supply > _DEAD_SHARES ? supply - _DEAD_SHARES : 0
        ];

        for (uint256 i = 0; i < 3; i++) {
            uint256 s = testShares[i];
            if (s == 0 || s > supply) continue;

            uint256 assets = vault.convertToAssets(s);
            if (assets == 0) continue;

            uint256 backToShares = vault.convertToShares(assets);

            // Floor rounding permits at most +1 share discrepancy
            assertLe(
                backToShares,
                s + 1,
                "INV-C: shares->assets->shares round-trip created free shares"
            );
        }
    }

    function invariant_D_solvency() public view {
        uint256 supply = vault.totalSupply();
        if (supply <= _DEAD_SHARES) return;

        uint256 redeemableSupply = supply - _DEAD_SHARES;
        uint256 assetsOwed = vault.convertToAssets(redeemableSupply);

        assertGe(
            vault.totalAssets(),
            assetsOwed,
            "INV-D: vault insolvent - totalAssets < assets owed to redeemable shares"
        );
    }

    function invariant_E_rebalanceNeutrality() public view {
        assertFalse(
            handler.ghostRebalanceViolated(),
            "INV-E: rebalance mutated share balances or totalSupply"
        );
    }

    function invariant_F_totalValueConsistency() public view {
        uint256 supply = vault.totalSupply();
        if (supply == 0) return;

        uint256 ta = vault.totalAssets();
        uint256 impliedAssets = vault.convertToAssets(supply);

        // Allow ±1 for integer floor rounding in mulDiv
        assertApproxEqAbs(
            impliedAssets,
            ta,
            1,
            "INV-F: convertToAssets(totalSupply) diverged from totalAssets()"
        );
    }

    function invariant_G_feeCompoundingSafety() public view {
        assertFalse(
            handler.ghostCompoundViolated(),
            "INV-G: collectFees reduced totalAssets with performanceFeeBps == 0"
        );
    }

    function invariant_H_deadSharesIntegrity() public view {
        uint256 supply = vault.totalSupply();
        if (supply == 0) return; // no first deposit yet

        assertEq(
            vault.balanceOf(address(0xdead)),
            _DEAD_SHARES,
            "INV-H: dead-share balance changed - inflation guard broken"
        );
    }

    function invariant_I_sharePricePositive() public view {
        uint256 supply = vault.totalSupply();
        if (supply <= _DEAD_SHARES) return;

        assertGt(
            vault.sharePrice(),
            0,
            "INV-I: share price is zero while real shares exist"
        );
    }

    function invariant_J_adminStateConsistency() public view {
        assertNotEq(
            vault.owner(),
            address(0),
            "INV-J: vault owner is zero address - vault is permanently bricked"
        );

        assertLe(
            vault.performanceFeeBps(),
            1000,
            "INV-J: performanceFeeBps exceeded 10% hard cap"
        );

        if (vault.paused()) {
            assertEq(
                vault.maxDeposit(address(this)),
                0,
                "INV-J: paused but maxDeposit != 0"
            );
            assertEq(
                vault.maxMint(address(this)),
                0,
                "INV-J: paused but maxMint != 0"
            );
        }
    }

    function afterInvariant() public view {
        uint256 totalCalls = handler.depositCalls() +
            handler.depositToken1Calls() +
            handler.redeemCalls() +
            handler.rebalanceCalls() +
            handler.compoundCalls() +
            handler.priceMoveCalls();

        uint256 totalReverts = handler.depositReverts() +
            handler.depositToken1Reverts() +
            handler.redeemReverts() +
            handler.rebalanceReverts() +
            handler.compoundReverts();

        console.log("-----------------------------------------");
        console.log("INVARIANT CAMPAIGN SUMMARY");
        console.log("-----------------------------------------");
        console.log("Total calls:    ", totalCalls);
        console.log("Total reverts:  ", totalReverts);
        if (totalCalls > 0) {
            console.log("Revert rate (%%):", (totalReverts * 100) / totalCalls);
        }

        console.log("");
        console.log(
            "  deposit        calls/reverts:",
            handler.depositCalls(),
            handler.depositReverts()
        );
        console.log(
            "  depositToken1  calls/reverts:",
            handler.depositToken1Calls(),
            handler.depositToken1Reverts()
        );
        console.log(
            "  redeem         calls/reverts:",
            handler.redeemCalls(),
            handler.redeemReverts()
        );
        console.log(
            "  rebalance      calls/reverts:",
            handler.rebalanceCalls(),
            handler.rebalanceReverts()
        );
        console.log(
            "  compoundFees   calls/reverts:",
            handler.compoundCalls(),
            handler.compoundReverts()
        );
        console.log("  movePrice      calls:", handler.priceMoveCalls());

        console.log("");
        console.log("VAULT STATE");
        console.log("  tokenId:     ", vault.tokenId());
        console.log("  totalSupply: ", vault.totalSupply());
        console.log("  totalAssets: ", vault.totalAssets());
        console.log("  sharePrice:  ", vault.sharePrice());
        console.log("  paused:      ", vault.paused());

        console.log("");
        console.log("ACTOR SHARE DISTRIBUTION");
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            address actor = handler.actors(i);
            uint256 bal = vault.balanceOf(actor);
            uint256 ghost = handler.ghostShares(actor);
            console.log("  actor index:", i);
            console.log("    balanceOf:", bal, "  ghost:", ghost);
        }
        console.log("  0xdead bal:", vault.balanceOf(address(0xdead)));

        console.log("");
        console.log("GHOST FLAGS");
        console.log("  rebalanceViolated:", handler.ghostRebalanceViolated());
        console.log("  compoundViolated: ", handler.ghostCompoundViolated());
        console.log("-----------------------------------------");
    }
}
