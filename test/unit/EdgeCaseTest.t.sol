// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../BaseTest.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

contract EdgeCaseTest is BaseTest {
    int24 internal LO;
    int24 internal HI;

    function setUp() public override {
        super.setUp();
        LO = ((TICK_100K - 2000) / TICK_SPACING) * TICK_SPACING;
        HI = ((TICK_100K + 2000) / TICK_SPACING) * TICK_SPACING;
    }

    function test_extremeVolatility() public {
        pool.setPrice(SQRT_PRICE_100K, TICK_100K + 300);

        vm.prank(alice);
        vm.expectRevert();
        vault.depositToken1(1e18, alice);

        // Price snaps back — ops resume.
        pool.setPrice(SQRT_PRICE_100K, TICK_100K + 50);
        vm.prank(alice);
        assertGt(vault.deposit(10e18, alice), 0);
    }

    function test_lowLiquidity() public {
        MockPositionManager(PM_ADDR).setMintReturn(0, 0, 0);

        vm.startPrank(owner);
        token0.transfer(address(vault), 1e18);
        vm.expectRevert();
        vault.initializePosition(LO, HI, 0, 0, 0, 0);
        vm.stopPrank();
    }

    function test_gas_depositUnderCeiling() public {
        uint256 gasBefore = gasleft();
        vm.prank(alice);
        vault.deposit(10e18, alice);
        assertLt(
            gasBefore - gasleft(),
            500_000,
            "deposit gas ceiling exceeded"
        );
    }

    function test_failedRebalance() public {
        _initialDeposit(10e18);
        _initPosition(LO, HI, 5e18, 0);
        uint256 oldTokenId = vault.tokenId();

        // Force the position manager's mint leg of rebalance to revert so we
        // can assert the burn-then-remint sequence doesn't commit partial state.
        MockPositionManager(PM_ADDR).setShouldRevert(true, false, false);

        vm.prank(operator);
        vm.expectRevert();
        vault.rebalance(false, 0);

        assertEq(vault.tokenId(), oldTokenId);
    }
}
