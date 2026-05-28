// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./UnitBase.sol";

contract ConstructorTest is UnitBase {
    function test_constructor_setsOwner() public view {
        assertEq(vault.owner(), owner);
    }

    function test_constructor_setsOperator() public view {
        assertEq(vault.operator(), operator);
    }

    function test_constructor_setsPool() public view {
        assertEq(address(vault.pool()), address(pool));
    }

    function test_constructor_setsTokens() public view {
        assertEq(address(vault.token0()), address(token0));
        assertEq(address(vault.token1()), address(token1));
    }

    function test_constructor_notPaused() public view {
        assertFalse(vault.paused());
    }

    function test_constructor_revertsZeroOwner() public {
        vm.expectRevert(RebalancerVault.ZeroAddress.selector);
        new RebalancerVault(address(0), address(pool), operator, "x", "x");
    }

    function test_constructor_revertsZeroOperator() public {
        vm.expectRevert(RebalancerVault.ZeroAddress.selector);
        new RebalancerVault(owner, address(pool), address(0), "x", "x");
    }

    function test_constructor_revertsZeroPool() public {
        vm.expectRevert();
        new RebalancerVault(owner, address(0), operator, "x", "x");
    }
}
