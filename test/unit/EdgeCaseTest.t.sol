// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../BaseTest.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

/// @notice Edge cases: extreme volatility, low-liquidity pools, gas bounds,
///         and failed rebalance scenarios.
contract EdgeCaseTest is BaseTest {
    int24 internal LO;
    int24 internal HI;

    function setUp() public override {
        super.setUp();
        LO = ((TICK_100K - 2000) / TICK_SPACING) * TICK_SPACING;
        HI = ((TICK_100K + 2000) / TICK_SPACING) * TICK_SPACING;
    }

    /// @dev Spot tick > maxTwapDeviationTicks blocks all ops; resuming after
    ///      price stabilizes confirms the guard is transient, not permanent.
    function test_extremeVolatility() public {
        pool.setPrice(SQRT_PRICE_100K, TICK_100K + 300);

        vm.prank(alice);
        vm.expectRevert();
        vault.depositToken1(1e18, alice);

        // Price snaps back — ops resume.
        pool.setPrice(SQRT_PRICE_100K, TICK_100K + 50);
        vm.prank(alice);
        assertGt(vault.deposit(10e8, alice), 0);
    }

    // ── Low liquidity pools ───────────────────────────────────────────────────

    /// @dev initializePosition reverts when the position manager returns zero
    ///      liquidity, confirming the NoLiquidityMinted guard fires.
    function test_lowLiquidity() public {
        MockPositionManager(PM_ADDR).setMintReturn(0, 0, 0);

        vm.startPrank(owner);
        token0.transfer(address(vault), 1e8);
        vm.expectRevert();
        vault.initializePosition(LO, HI, 1e8, 0, 0, 0);
        vm.stopPrank();
    }

    // ── Gas cost optimization ─────────────────────────────────────────────────

    /// @dev Deposit gas must stay under a conservative ceiling.
    function test_gas_depositUnderCeiling() public {
        uint256 gasBefore = gasleft();
        vm.prank(alice);
        vault.deposit(10e8, alice);
        assertLt(gasBefore - gasleft(), 500_000, "deposit gas ceiling exceeded");
    }

    // ── Failed rebalances ─────────────────────────────────────────────────────

    /// @dev Re-mint failure reverts the entire transaction — tokenId is
    ///      unchanged, proving no partial state is committed.
    function test_failedRebalance() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);
        uint256 oldTokenId = vault.tokenId();

        MockPositionManager(PM_ADDR).setShouldRevert(true, false, false);

        vm.prank(operator);
        vm.expectRevert();
        vault.rebalance(false, 0);

        assertEq(vault.tokenId(), oldTokenId);
    }
}
