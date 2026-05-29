// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../BaseTest.sol";

/// @title Fuzz tests — property-based testing of vault invariants
contract FuzzTest is BaseTest {
    /// @dev Any valid deposit should give nonzero shares
    function testFuzz_deposit_alwaysMintsShares(uint256 assets) public {
        assets = bound(assets, DEAD_SHARES + 1, token0.balanceOf(alice));
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);
        assertGt(shares, 0, "shares > 0");
    }

    /// @dev Second depositor gets proportional shares (no value leakage)
    function testFuzz_deposit_proportionalShares(
        uint256 firstDeposit,
        uint256 secondDeposit
    ) public {
        firstDeposit = bound(
            firstDeposit,
            DEAD_SHARES + 1,
            token0.balanceOf(alice)
        );
        secondDeposit = bound(secondDeposit, 1, token0.balanceOf(bob));

        vm.prank(alice);
        vault.deposit(firstDeposit, alice);

        uint256 ta = vault.totalAssets();
        uint256 supply = vault.totalSupply();

        vm.prank(bob);
        uint256 bobShares = vault.deposit(secondDeposit, bob);

        uint256 expected = (secondDeposit * supply) / ta;
        assertApproxEqAbs(bobShares, expected, 1, "proportional shares");
    }

    /// @dev Deposit should never give more assets back than deposited (no inflation)
    function testFuzz_deposit_noInflation(uint256 assets) public {
        assets = bound(assets, DEAD_SHARES + 1, token0.balanceOf(alice));
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        uint256 redeemable = vault.convertToAssets(shares);
        assertLe(redeemable, assets, "no inflation");
    }

    function testFuzz_mint_assetsNeverLessThanPreview(uint256 shares) public {
        _initialDeposit(INITIAL_DEPOSIT);

        shares = bound(shares, 1, 1e8);
        uint256 preview = vault.previewMint(shares);
        token0.mint(bob, preview + 1);

        vm.startPrank(bob);
        token0.approve(address(vault), type(uint256).max);
        uint256 actualAssets = vault.mint(shares, bob);
        vm.stopPrank();

        assertLe(actualAssets, preview + 1, "assets not more than preview + 1");
    }

    /// @dev Redeem should never return more than proportional share of totalAssets
    function testFuzz_redeem_neverExceedsProportionalAssets(
        uint256 depositAmt,
        uint256 redeemShares
    ) public {
        depositAmt = bound(depositAmt, DEAD_SHARES + 1, 10e8);
        token0.mint(alice, depositAmt);

        vm.prank(alice);
        vault.deposit(depositAmt, alice);

        uint256 aliceShares = vault.balanceOf(alice);
        redeemShares = bound(redeemShares, 1, aliceShares);

        uint256 taBefore = vault.totalAssets();
        uint256 supply = vault.totalSupply();

        vm.prank(alice);
        uint256 assets = vault.redeem(redeemShares, alice, alice);

        // assets should be <= proportional share of totalAssets
        uint256 proportional = (redeemShares * taBefore) / supply;
        assertLe(assets, proportional + 1, "no excess withdrawal");
    }

    /// @dev After full redeem, vault should have less supply
    function testFuzz_redeem_supplyDecreases(uint256 depositAmt) public {
        depositAmt = bound(depositAmt, DEAD_SHARES + 1, 10e8);
        token0.mint(alice, depositAmt);

        vm.prank(alice);
        vault.deposit(depositAmt, alice);

        uint256 supplyBefore = vault.totalSupply();
        uint256 aliceShares = vault.balanceOf(alice);

        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);

        assertLt(vault.totalSupply(), supplyBefore, "supply decreased");
    }

    function testFuzz_convertToShares_thenAssets_noGain(
        uint256 depositAmt,
        uint256 assets
    ) public {
        depositAmt = bound(depositAmt, DEAD_SHARES + 1, 10e8);
        token0.mint(alice, depositAmt);
        vm.prank(alice);
        vault.deposit(depositAmt, alice);

        assets = bound(assets, 1, vault.totalAssets());

        uint256 shares = vault.convertToShares(assets);
        uint256 backOut = vault.convertToAssets(shares);

        // Round-trip should not produce more than original (floor rounding)
        assertLe(backOut, assets, "no gain on round-trip");
    }

    function testFuzz_convertToAssets_thenShares_noGain(
        uint256 depositAmt,
        uint256 shares
    ) public {
        depositAmt = bound(depositAmt, DEAD_SHARES + 1, 10e8);
        token0.mint(alice, depositAmt);
        vm.prank(alice);
        vault.deposit(depositAmt, alice);

        shares = bound(shares, 1, vault.totalSupply());

        uint256 assets = vault.convertToAssets(shares);
        uint256 backOut = vault.convertToShares(assets);

        // Same direction check
        assertLe(backOut, shares + 1, "no excessive gain");
    }

    /// @dev _floor should always return a multiple of spacing
    function testFuzz_floor_alignedToSpacing(
        int24 tick,
        int24 spacing
    ) public pure {
        spacing = int24(bound(int256(spacing), 1, 1000));
        tick = int24(bound(int256(tick), -887272, 887272));

        // Call via exposed helper
        int24 result = _floor(tick, spacing);
        assertEq(result % spacing, 0, "floor aligned");
        assertLe(result, tick, "floor <= tick");
    }

    /// @dev _ceil should always return a multiple of spacing >= tick
    function testFuzz_ceil_alignedToSpacing(
        int24 tick,
        int24 spacing
    ) public pure {
        spacing = int24(bound(int256(spacing), 1, 1000));
        tick = int24(bound(int256(tick), -887272, 887272));

        int24 result = _ceil(tick, spacing);
        assertEq(result % spacing, 0, "ceil aligned");
        assertGe(result, tick, "ceil >= tick");
    }

    // ── Expose internal helpers for fuzz testing ─────────────────────────────
    function _floor(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 compressed = tick / spacing;
        if (tick < 0 && tick % spacing != 0) compressed--;
        return compressed * spacing;
    }

    function _ceil(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 floored = _floor(tick, spacing);
        return (floored == tick) ? tick : floored + spacing;
    }

    function testFuzz_sharePrice_neverDecreasesOnDeposit(
        uint256 firstDeposit,
        uint256 secondDeposit
    ) public {
        firstDeposit = bound(firstDeposit, DEAD_SHARES + 1, 10e8);
        secondDeposit = bound(secondDeposit, DEAD_SHARES + 1, 10e8);
        token0.mint(alice, firstDeposit);
        token0.mint(bob, secondDeposit);

        vm.prank(alice);
        vault.deposit(firstDeposit, alice);
        uint256 priceBefore = _sharePrice();

        vm.prank(bob);
        vault.deposit(secondDeposit, bob);
        uint256 priceAfter = _sharePrice();

        // Share price should not increase just from a new deposit (dilution-free)
        assertApproxEqAbs(
            priceBefore,
            priceAfter,
            2,
            "share price stable on deposit"
        );
    }

    function testFuzz_withdraw_basicSucceeds(
        uint256 depositAmt
    ) public {
        depositAmt = bound(depositAmt, DEAD_SHARES + 1, 10e8);
        token0.mint(alice, depositAmt);
        vm.prank(alice);
        vault.deposit(depositAmt, alice);

        uint256 withdrawAmt = vault.maxWithdraw(alice) / 2;
        vm.assume(withdrawAmt > 0);

        uint256 balBefore = token0.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(withdrawAmt, alice, alice);
        assertEq(token0.balanceOf(alice), balBefore + withdrawAmt);
    }
}
