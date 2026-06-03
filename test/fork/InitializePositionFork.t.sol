// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/RebalancerVaultUpgradeable.sol";
import "../../src/adapters/CLDexAdapter.sol";
import {IDexAdapter} from "../../src/adapters/interfaces/IDexAdapter.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/INonfungiblePositionManager.sol";

contract InitializePositionForkTest is Test {
    // ── Real testnet addresses ───────────────────────────────────────────────
    address constant VAULT = 0xA22F4E89135d88B11Bdcaecf756ff7B3e8d37dD0;
    address constant TOKEN0 = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503; // MUSD
    address constant TOKEN1 = 0x7b7C000000000000000000000000000000000000; // BTC
    address constant POS_MGR = 0x509Bc221df2B83927c695FA0bb0f5B21053C874c;
    address constant OWNER = 0xe4F4c768d628074C8a975126D517a60A03848f69;

    RebalancerVaultUpgradeable vault;

    function setUp() public {
        vm.createSelectFork("https://rpc.test.mezo.org");
        vault = RebalancerVaultUpgradeable(payable(VAULT));
    }

    // ── Step 1: verify vault state ───────────────────────────────────────────
    function test_vaultState() public view {
        assertEq(vault.owner(), OWNER, "owner mismatch");
        assertFalse(vault.paused(), "vault is paused");
        assertEq(vault.tokenId(), 0, "already initialized");
        assertEq(address(vault.token0()), TOKEN0, "wrong token0");
        assertEq(address(vault.token1()), TOKEN1, "wrong token1");
    }

    // ── Step 2: verify vault has tokens ─────────────────────────────────────
    function test_vaultBalances() public view {
        uint256 bal0 = IERC20(TOKEN0).balanceOf(VAULT);
        uint256 bal1 = IERC20(TOKEN1).balanceOf(VAULT);
        console.log("token0 balance:", bal0);
        console.log("token1 balance:", bal1);
        assertGt(bal0, 0, "no token0 in vault");
        assertGt(bal1, 0, "no token1 in vault");
    }

    // ── Step 3: isolate token0 approve ──────────────────────────────────────
    function test_token0Approve() public {
        vm.prank(VAULT);
        bool ok = IERC20(TOKEN0).approve(POS_MGR, type(uint256).max);
        assertTrue(ok, "token0 approve failed");
        console.log(
            "token0 allowance:",
            IERC20(TOKEN0).allowance(VAULT, POS_MGR)
        );
    }

    // ── Step 4: isolate token1 approve ──────────────────────────────────────
    function test_token1Approve() public {
        vm.prank(VAULT);
        bool ok = IERC20(TOKEN1).approve(POS_MGR, type(uint256).max);
        assertTrue(ok, "token1 approve failed");
        console.log(
            "token1 allowance:",
            IERC20(TOKEN1).allowance(VAULT, POS_MGR)
        );
    }

    // ── CLDexAdapter.mint fork tests ─────────────────────────────────────────

    // Helper: deploy adapter and fund caller with tokens from the vault
    function _adapterAndFunds(
        uint256 amount0,
        uint256 amount1
    ) internal returns (CLDexAdapter adapter) {
        adapter = new CLDexAdapter();
        // steal tokens from the vault (it already holds balances)
        vm.prank(VAULT);
        IERC20(TOKEN0).transfer(address(this), amount0);
        vm.prank(VAULT);
        IERC20(TOKEN1).transfer(address(this), amount1);
        IERC20(TOKEN0).approve(address(adapter), amount0);
        IERC20(TOKEN1).approve(address(adapter), amount1);
    }

    function test_adapterMint_returnsPositiveTokenId() public {
        uint256 amt0 = 1e18;
        uint256 amt1 = 1e4; // BTC has 8 decimals; small amount
        CLDexAdapter adapter = _adapterAndFunds(amt0, amt1);

        (uint256 tokenId, uint128 liquidity, , ) = adapter.mint(
            IDexAdapter.MintArgs({
                positionManager: POS_MGR,
                token0: TOKEN0,
                token1: TOKEN1,
                tickSpacing: 50,
                tickLower: -114750,
                tickUpper: -113300,
                amount0Desired: amt0,
                amount1Desired: amt1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 1 hours
            })
        );

        assertGt(tokenId, 0, "tokenId must be non-zero");
        assertGt(liquidity, 0, "liquidity must be non-zero");
    }

    function test_adapterMint_recipientReceivesNFT() public {
        uint256 amt0 = 1e18;
        uint256 amt1 = 1e4;
        CLDexAdapter adapter = _adapterAndFunds(amt0, amt1);

        address recipient = makeAddr("recipient");

        (uint256 tokenId, , , ) = adapter.mint(
            IDexAdapter.MintArgs({
                positionManager: POS_MGR,
                token0: TOKEN0,
                token1: TOKEN1,
                tickSpacing: 50,
                tickLower: -114750,
                tickUpper: -113300,
                amount0Desired: amt0,
                amount1Desired: amt1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: recipient,
                deadline: block.timestamp + 1 hours
            })
        );

        assertEq(
            INonfungiblePositionManager(POS_MGR).ownerOf(tokenId),
            recipient,
            "NFT not sent to recipient"
        );
    }

    function test_adapterMint_consumesTokens() public {
        uint256 amt0 = 1e18;
        uint256 amt1 = 1e4;
        CLDexAdapter adapter = _adapterAndFunds(amt0, amt1);

        uint256 pre0 = IERC20(TOKEN0).balanceOf(address(this));
        uint256 pre1 = IERC20(TOKEN1).balanceOf(address(this));

        (, , uint256 used0, uint256 used1) = adapter.mint(
            IDexAdapter.MintArgs({
                positionManager: POS_MGR,
                token0: TOKEN0,
                token1: TOKEN1,
                tickSpacing: 50,
                tickLower: -114750,
                tickUpper: -113300,
                amount0Desired: amt0,
                amount1Desired: amt1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 1 hours
            })
        );

        uint256 post0 = IERC20(TOKEN0).balanceOf(address(this));
        uint256 post1 = IERC20(TOKEN1).balanceOf(address(this));

        assertEq(pre0 - post0, used0, "token0 balance delta mismatch");
        assertEq(pre1 - post1, used1, "token1 balance delta mismatch");
        assertGt(used0 + used1, 0, "no tokens consumed");
    }

    function test_adapterMint_revertsAfterDeadline() public {
        uint256 amt0 = 1e18;
        uint256 amt1 = 1e4;
        CLDexAdapter adapter = _adapterAndFunds(amt0, amt1);

        vm.expectRevert();
        adapter.mint(
            IDexAdapter.MintArgs({
                positionManager: POS_MGR,
                token0: TOKEN0,
                token1: TOKEN1,
                tickSpacing: 50,
                tickLower: -114750,
                tickUpper: -113300,
                amount0Desired: amt0,
                amount1Desired: amt1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp - 1 // already expired
            })
        );
    }

    // ── Step 5: full initializePosition ─────────────────────────────────────
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
