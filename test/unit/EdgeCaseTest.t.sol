// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./UnitBase.sol";

contract EdgeCaseTest is UnitBase {
    // ── Inflation attack ──────────────────────────────────────────────────────

    function test_inflationAttack_deadSharesPreventsIt() public {
        uint256 attackDeposit = 1;
        token0.mint(address(this), attackDeposit);
        token0.approve(address(vault), attackDeposit);
        vault.deposit(attackDeposit, address(this));

        token0.mint(address(vault), 100e18);

        vm.prank(alice);
        uint256 aliceShares = vault.deposit(100e18, alice);
        assertGt(aliceShares, 0);
        vm.roll(block.number + 1);

        vm.prank(alice);
        assertGt(vault.redeem(aliceShares, alice, alice), 0);
    }

    // ── Dead-shares boundary ──────────────────────────────────────────────────

    function test_deposit_exactlyDeadShares_reverts() public {
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.BelowMinDeposit.selector);
        vault.deposit(DEAD_SHARES, alice);
    }

    function test_deposit_deadSharesPlusOne_mints1Share() public {
        vm.prank(alice);
        assertEq(vault.deposit(DEAD_SHARES + 1, alice), 1);
    }

    function test_redeem_fullRedeemLeavesDeadShares() public {
        vm.prank(alice);
        vault.deposit(10e8, alice);
        vm.roll(block.number + 1);
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);
        assertEq(vault.totalSupply(), DEAD_SHARES);
    }

    // ── Zero-supply view functions ────────────────────────────────────────────

    function test_convertToShares_zeroSupply_returnsInput() public view {
        assertEq(vault.convertToShares(1e8), 1e8);
    }

    function test_convertToShares_maxUint128_zeroSupply_returnsInput()
        public
        view
    {
        assertEq(vault.convertToShares(type(uint128).max), type(uint128).max);
    }

    function test_previewWithdraw_zeroSupply_returnsMaxUint() public view {
        assertEq(vault.previewWithdraw(1e8), type(uint256).max);
    }

    function test_previewWithdraw_afterDeposit_returnsFiniteValue() public {
        _initialDeposit(INITIAL_DEPOSIT);
        assertLt(vault.previewWithdraw(type(uint128).max), type(uint256).max);
    }

    // ── Tick alignment ────────────────────────────────────────────────────────

    function test_rebalance_negativeTick_newRangeAligned() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);
        pool.setPrice(1e10, -400);

        vm.prank(operator);
        vault.rebalance(false, 0, RebalancerVault.StrategyType.MEDIUM);

        (, , , , , int24 newLo, int24 newHi, , , , , ) = _pm().positions(
            vault.tokenId()
        );
        int24 spacing = pool.tickSpacing();
        assertEq(newLo % spacing, 0);
        assertEq(newHi % spacing, 0);
    }

    function test_rebalance_extremePositiveTick_newRangeAligned() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);
        pool.setPrice(SQRT_PRICE_100K, 880000);

        vm.prank(operator);
        vault.rebalance(false, 0, RebalancerVault.StrategyType.MEDIUM);

        (, , , , , int24 newLo, int24 newHi, , , , , ) = _pm().positions(
            vault.tokenId()
        );
        int24 spacing = pool.tickSpacing();
        assertEq(newLo % spacing, 0);
        assertEq(newHi % spacing, 0);
    }

    function test_initializePosition_equalTicks_reverts() public {
        int24 tick = (TICK_100K / TICK_SPACING) * TICK_SPACING;
        vm.prank(owner);
        vm.expectRevert(RebalancerVault.InvalidRange.selector);
        vault.initializePosition(tick, tick, 1e7, 1e15, 0, 0);
    }

    // ── isOutOfRange boundary ─────────────────────────────────────────────────

    function test_isOutOfRange_tickAtTickLower_isInRange() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);
        pool.setPrice(SQRT_PRICE_100K, lo);
        assertFalse(vault.isOutOfRange());
    }

    function test_isOutOfRange_tickAtTickUpper_isOutOfRange() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);
        pool.setPrice(SQRT_PRICE_100K, hi);
        assertTrue(vault.isOutOfRange());
    }

    // ── Overflow resistance ───────────────────────────────────────────────────

    function test_totalAssets_largeToken1Idle_noOverflow() public {
        _initialDeposit(10e8);
        token1.mint(address(vault), type(uint128).max);
        vault.totalAssets();
    }

    // ── Gas budgets ───────────────────────────────────────────────────────────

    function test_gas_deposit() public {
        uint256 gas = gasleft();
        vm.prank(alice);
        vault.deposit(INITIAL_DEPOSIT, alice);
        assertLt(gas - gasleft(), 300_000);
    }

    function test_gas_redeem() public {
        _initialDeposit(INITIAL_DEPOSIT);
        uint256 shares = vault.balanceOf(alice);
        uint256 gas = gasleft();
        vm.prank(alice);
        vault.redeem(shares / 2, alice, alice);
        assertLt(gas - gasleft(), 300_000);
    }

    function test_gas_rebalance() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);
        uint256 gas = gasleft();
        vm.prank(operator);
        vault.rebalance(false, 0, RebalancerVault.StrategyType.MEDIUM);
        assertLt(gas - gasleft(), 500_000);
    }

    function test_gas_collectFees() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);
        _pm().setPendingFees(vault.tokenId(), 1e6, 1e14);
        uint256 gas = gasleft();
        vm.prank(operator);
        vault.collectFees(0, 0);
        assertLt(gas - gasleft(), 200_000);
    }

    // ── Allowance enforcement ─────────────────────────────────────────────────

    function test_redeem_withoutAllowance_reverts() public {
        _initialDeposit(INITIAL_DEPOSIT);
        vm.prank(bob);
        vm.expectRevert();
        vault.redeem(1, bob, alice);
    }

    function test_withdraw_withoutAllowance_reverts() public {
        _initialDeposit(INITIAL_DEPOSIT);
        vm.prank(bob);
        vm.expectRevert();
        vault.withdraw(1e6, bob, alice);
    }

    // ── Sweep protection ──────────────────────────────────────────────────────

    function test_sweepToken_cannotStealToken0() public {
        _initialDeposit(INITIAL_DEPOSIT);
        vm.prank(owner);
        vm.expectRevert(RebalancerVault.InvalidToken.selector);
        vault.sweepToken(address(token0), owner);
    }

    function test_sweepToken_cannotStealToken1() public {
        token1.mint(address(vault), 1e18);
        vm.prank(owner);
        vm.expectRevert(RebalancerVault.InvalidToken.selector);
        vault.sweepToken(address(token1), owner);
    }

    // ── Not-initialized guard ─────────────────────────────────────────────────

    function test_getPosition_notInitialized_reverts() public {
        vm.expectRevert(RebalancerVault.NotInitialized.selector);
        vault.getPosition();
    }

    // ── Ether handling ────────────────────────────────────────────────────────

    function test_receive_ether_accepted() public {
        (bool ok, ) = address(vault).call{value: 1 ether}("");
        assertTrue(ok);
    }

    // ── Rebalance edge cases ──────────────────────────────────────────────────

    function test_rebalance_withSwap_zeroSlippage_doesNotRevert() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);
        vm.prank(alice);
        vault.deposit(5e8, alice);
        vm.prank(operator);
        vault.rebalance(true, 1e6, RebalancerVault.StrategyType.MEDIUM);
    }

    function test_rebalance_lowLiquidityPosition_succeeds() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _pm().setMintReturn(1, 0, 0);
        _initPosition(lo, hi, 1e7, 1e15);
        vm.prank(operator);
        vault.rebalance(false, 0, RebalancerVault.StrategyType.MEDIUM);
        assertGt(vault.tokenId(), 0);
    }
}
