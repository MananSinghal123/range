// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {VaultStorageLib} from "../../src/libraries/VaultStorageLib.sol";

contract StorageSlotTest is Test {
    function test_namespaceSlotMatchesERC7201Formula() public pure {
        bytes32 expected = keccak256(
            abi.encode(uint256(keccak256("mezo.storage.RebalancerVault")) - 1)
        ) & ~bytes32(uint256(0xff));
        assertEq(VaultStorageLib.STORAGE_SLOT(), expected);
    }
}
