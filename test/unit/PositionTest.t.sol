// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./UnitBase.sol";

contract PositionTest is UnitBase {
    // ─── initializePosition ───────────────────────────────────────────────────

    function test_initializePosition_setsTokenId() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initPosition(lo, hi, 5e7, 0);

        assertGt(vault.tokenId(), 0);
    }

    function test_initializePosition_revertsAlreadyInitialized() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initPosition(lo, hi, 5e7, 0);

        vm.startPrank(owner);
        vm.expectRevert(RebalancerVault.AlreadyInitialized.selector);
        vault.initializePosition(lo, hi, 1e7, 0, 0, 0);
        vm.stopPrank();
    }

    function test_initializePosition_revertsInvalidRange_equalTicks() public {
        vm.prank(owner);
        vm.expectRevert(RebalancerVault.InvalidRange.selector);
        vault.initializePosition(1000, 1000, 1e7, 0, 0, 0);
    }

    function test_initializePosition_revertsInvalidRange_invertedTicks() public {
        vm.prank(owner);
        vm.expectRevert(RebalancerVault.InvalidRange.selector);
        vault.initializePosition(2000, 1000, 1e7, 0, 0, 0);
    }

    function test_initializePosition_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.NotOwner.selector);
        vault.initializePosition(-1000, 1000, 1e7, 0, 0, 0);
    }

    function test_initializePosition_revertsNoLiquidityMinted() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _pm().setMintReturn(0, 0, 0);

        vm.startPrank(owner);
        token0.transfer(address(vault), 5e7);
        vm.expectRevert(RebalancerVault.NoLiquidityMinted.selector);
        vault.initializePosition(lo, hi, 5e7, 0, 0, 0);
        vm.stopPrank();

        _pm().setMintReturn(1e18, 0, 0);
    }

    function test_initializePosition_revertsWhenPaused() public {
        vm.prank(owner);
        vault.setPaused(true);

        vm.prank(owner);
        vm.expectRevert("Vault: paused");
        vault.initializePosition(-1000, 1000, 0, 0, 0, 0);
    }

    function test_initializePosition_pullsTokensFromVault() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();

        // _initPosition adds 5e7 to vault, then initializePosition causes PM to pull it.
        uint256 pmBal0Before = token0.balanceOf(address(_pm()));
        _initPosition(lo, hi, 5e7, 0);

        assertEq(token0.balanceOf(address(_pm())), pmBal0Before + 5e7);
    }

    // ─── collectFees ──────────────────────────────────────────────────────────

    function test_collectFees_revertsNotInitialized() public {
        vm.prank(operator);
        vm.expectRevert(RebalancerVault.NotInitialized.selector);
        vault.collectFees(0, 0);
    }

    function test_collectFees_revertsIfNotOperator() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initPosition(lo, hi, 5e7, 0);

        vm.prank(alice);
        vm.expectRevert(RebalancerVault.NotOperator.selector);
        vault.collectFees(0, 0);
    }

    function test_collectFees_revertsWhenPaused() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initPosition(lo, hi, 5e7, 0);
        vm.prank(owner);
        vault.setPaused(true);

        vm.prank(operator);
        vm.expectRevert("Vault: paused");
        vault.collectFees(0, 0);
    }

    function test_collectFees_noFees_returnsZero() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initPosition(lo, hi, 5e7, 0);

        vm.prank(operator);
        (uint256 net0, uint256 net1) = vault.collectFees(0, 0);

        assertEq(net0, 0);
        assertEq(net1, 0);
    }

    function test_collectFees_withFees_vaultReceivesTokens() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initPosition(lo, hi, 5e7, 0);

        _pm().setPendingFees(vault.tokenId(), 1e6, 1e16);

        uint256 bal0Before = token0.balanceOf(address(vault));
        uint256 bal1Before = token1.balanceOf(address(vault));

        vm.prank(operator);
        vault.collectFees(0, 0);

        assertGt(token0.balanceOf(address(vault)), bal0Before);
        assertGt(token1.balanceOf(address(vault)), bal1Before);
    }

    function test_collectFees_withPerformanceFee_deductsCorrectly() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initPosition(lo, hi, 5e7, 0);
        _setFee(500); // 5%

        uint256 gross0 = 1e6;
        uint256 gross1 = 1e16;
        _pm().setPendingFees(vault.tokenId(), gross0, gross1);

        vm.prank(operator);
        (uint256 net0, uint256 net1) = vault.collectFees(0, 0);

        uint256 cut0 = (gross0 * 500 + 9999) / 10000; // ceil
        uint256 cut1 = (gross1 * 500 + 9999) / 10000;
        assertEq(net0, gross0 - cut0);
        assertEq(net1, gross1 - cut1);
    }

    function test_collectFees_withPerformanceFee_paysRecipient() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initPosition(lo, hi, 5e7, 0);
        _setFee(1000); // 10%

        _pm().setPendingFees(vault.tokenId(), 1e6, 0);

        uint256 recipBefore = token0.balanceOf(feeRecip);

        vm.prank(operator);
        vault.collectFees(0, 0);

        assertGt(token0.balanceOf(feeRecip), recipBefore);
    }

    // ─── rebalance ────────────────────────────────────────────────────────────

    function test_rebalance_revertsNotInitialized() public {
        vm.prank(operator);
        vm.expectRevert(RebalancerVault.NotInitialized.selector);
        vault.rebalance(false, 0, RebalancerVault.StrategyType.MEDIUM);
    }

    function test_rebalance_revertsIfNotOperator() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);

        vm.prank(alice);
        vm.expectRevert(RebalancerVault.NotOperator.selector);
        vault.rebalance(false, 0, RebalancerVault.StrategyType.MEDIUM);
    }

    function test_rebalance_revertsWhenPaused() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);
        vm.prank(owner);
        vault.setPaused(true);

        vm.prank(operator);
        vm.expectRevert("Vault: paused");
        vault.rebalance(false, 0, RebalancerVault.StrategyType.MEDIUM);
    }

    function test_rebalance_updatesTokenId() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);

        uint256 oldTokenId = vault.tokenId();

        vm.prank(operator);
        vault.rebalance(false, 0, RebalancerVault.StrategyType.MEDIUM);

        assertGt(vault.tokenId(), oldTokenId);
    }

    function test_rebalance_burnsOldNFT() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);

        uint256 burnsBefore = _pm().burnCallCount();

        vm.prank(operator);
        vault.rebalance(false, 0, RebalancerVault.StrategyType.MEDIUM);

        assertEq(_pm().burnCallCount(), burnsBefore + 1);
    }

    function test_rebalance_newPositionCenteredOnCurrentTick() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);

        vm.prank(operator);
        vault.rebalance(false, 0, RebalancerVault.StrategyType.MEDIUM);

        uint256 newId = vault.tokenId();
        (, , , , , int24 nlo, int24 nhi, , , , , ) = vault.positionManager().positions(newId);

        assertLt(nlo, TICK_100K);
        assertGt(nhi, TICK_100K);
    }

    function test_rebalance_withSwap_callsSwapRouter() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);

        vm.prank(alice);
        vault.deposit(5e8, alice);

        uint256 swapBefore = MockCLSwapRouter(address(vault.clSwapRouter())).swapCallCount();

        vm.prank(operator);
        vault.rebalance(true, 1e7, RebalancerVault.StrategyType.MEDIUM);

        assertGt(
            MockCLSwapRouter(address(vault.clSwapRouter())).swapCallCount(),
            swapBefore
        );
    }

    function test_rebalance_deductsPerformanceFee() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);
        _setFee(500);

        _pm().setPendingFees(vault.tokenId(), 1e6, 0);

        uint256 recipBefore = token0.balanceOf(feeRecip);

        vm.prank(operator);
        vault.rebalance(false, 0, RebalancerVault.StrategyType.MEDIUM);

        assertGt(token0.balanceOf(feeRecip), recipBefore);
    }

    function test_rebalance_mintsNewPosition() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);

        uint256 mintsBefore = _pm().mintCallCount();

        vm.prank(operator);
        vault.rebalance(false, 0, RebalancerVault.StrategyType.MEDIUM);

        assertEq(_pm().mintCallCount(), mintsBefore + 1);
    }
}
