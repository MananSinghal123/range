// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../BaseTest.sol";

contract AdapterPlumbingTest is BaseTest {
    function test_setStrategy_ownerOnly() public {
        Strategy s2 = new Strategy(300);
        vm.prank(alice);
        vm.expectRevert();
        vault.setStrategy(address(s2));

        vm.prank(owner);
        vault.setStrategy(address(s2));
        assertEq(vault.strategy(), address(s2));
    }

    function test_setDexAdapter_ownerOnly() public {
        CLDexAdapter a2 = new CLDexAdapter();
        vm.prank(alice);
        vm.expectRevert();
        vault.setDexAdapter(address(a2));

        vm.prank(owner);
        vault.setDexAdapter(address(a2));
        assertEq(vault.dexAdapter(), address(a2));
    }

    function test_setStrategy_zeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert();
        vault.setStrategy(address(0));
    }

    function test_setDexAdapter_zeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert();
        vault.setDexAdapter(address(0));
    }
}
