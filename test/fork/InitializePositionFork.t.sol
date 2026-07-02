// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/RebalancerVaultUpgradeable.sol";
import "../../src/adapters/CLDexAdapter.sol";
import {IDexAdapter} from "../../src/adapters/interfaces/IDexAdapter.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/INonfungiblePositionManager.sol";
import "../mocks/MockERC20.sol";

contract InitializePositionForkTest is Test {
    address constant VAULT = 0x9b29b71829597A1B705Ea1Bab1C8B2fD00088594;
    address constant TOKEN0 = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503; // MUSD
    address constant TOKEN1 = 0x7b7C000000000000000000000000000000000000; // BTC
    address constant POS_MGR = 0x509Bc221df2B83927c695FA0bb0f5B21053C874c;
    address constant OWNER = 0xe4F4c768d628074C8a975126D517a60A03848f69;
    uint256 constant SHIMMED_BTC_BALANCE = 1_000_000e8;

    RebalancerVaultUpgradeable vault;

    function setUp() public {
        vm.createSelectFork("https://rpc.test.mezo.org");
        _shimToken1AsERC20();
        vault = RebalancerVaultUpgradeable(payable(VAULT));
    }

    function _shimToken1AsERC20() internal {
        MockERC20 shim = new MockERC20("Bitcoin", "BTC", 8);

        vm.etch(TOKEN1, address(shim).code);

        // OpenZeppelin ERC20 stores `_decimals` after balances, allowances,
        // totalSupply, name, and symbol.
        vm.store(TOKEN1, bytes32(uint256(5)), bytes32(uint256(8)));
        MockERC20(TOKEN1).mint(VAULT, SHIMMED_BTC_BALANCE);
    }

    // ── Step 1: verify vault state ───────────────────────────────────────────
    function test_vaultState() public view {
        assertEq(vault.owner(), OWNER, "owner mismatch");
        assertFalse(vault.paused(), "vault is paused");
        assertEq(vault.tokenId(), 0, "already initialized");
        assertEq(address(vault.token0()), TOKEN0, "wrong token0");
        assertEq(address(vault.token1()), TOKEN1, "wrong token1");
    }

    function test_vaultBalances() public view {
        uint256 bal0 = IERC20(TOKEN0).balanceOf(VAULT);
        uint256 bal1 = IERC20(TOKEN1).balanceOf(VAULT);
        console.log("token0 balance:", bal0);
        console.log("token1 balance:", bal1);
        assertGt(bal0, 0, "no token0 in vault");
        assertGt(bal1, 0, "no token1 in vault");
    }

    function test_token0Approve() public {
        vm.prank(VAULT);
        bool ok = IERC20(TOKEN0).approve(POS_MGR, type(uint256).max);
        assertTrue(ok, "token0 approve failed");
        console.log(
            "token0 allowance:",
            IERC20(TOKEN0).allowance(VAULT, POS_MGR)
        );
    }

    function test_token1Approve() public {
        vm.prank(VAULT);
        bool ok = IERC20(TOKEN1).approve(POS_MGR, type(uint256).max);
        assertTrue(ok, "token1 approve failed");
        console.log(
            "token1 allowance:",
            IERC20(TOKEN1).allowance(VAULT, POS_MGR)
        );
    }

    function test_initializePosition() public {
        vm.prank(OWNER);
        vault.initializePosition(
            -114750,
            -113300,
            1000000000000000000,
            100000,
            0,
            0
        );
        assertGt(vault.tokenId(), 0, "position not initialized");
        console.log("tokenId:", vault.tokenId());
    }
}
