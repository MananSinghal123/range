// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CLDexAdapter} from "../../src/adapters/CLDexAdapter.sol";
import {IDexAdapter} from "../../src/adapters/interfaces/IDexAdapter.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/INonfungiblePositionManager.sol";
import {ICLSwapRouter} from "../../src/interfaces/router/ICLSwapRouter.sol";

contract CLDexAdapterForkTest is Test {
    address constant POOL    = 0x026dB82AC7ABf60Bf1a81317c9DbD63702B85850;
    address constant TOKEN0  = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503; // MUSD
    address constant TOKEN1  = 0x7b7C000000000000000000000000000000000000; // BTC
    address constant POS_MGR = 0x509Bc221df2B83927c695FA0bb0f5B21053C874c;
    address constant ROUTER  = 0x3112908bB72ce9c26a321Eeb22EC8e051F3b6E6a;
    int24  constant TICK_SPACING = 50;

    int24 constant TICK_LO = -114750;
    int24 constant TICK_HI = -113300;

    CLDexAdapter adapter;

    function setUp() public {
        vm.createSelectFork("https://rpc.test.mezo.org");
        adapter = new CLDexAdapter();
    }

    function test_slot0_returnsNonZeroPrice() public view {
        (uint160 sqrtPriceX96, int24 tick) = adapter.slot0(POOL);
        assertGt(sqrtPriceX96, 0, "sqrtPriceX96 should be non-zero");
        console.log("sqrtPriceX96:", sqrtPriceX96);
        console.logInt(tick);
    }

    function test_tickSpacing_returns50() public view {
        int24 ts = adapter.tickSpacing(POOL);
        assertEq(ts, TICK_SPACING, "unexpected tick spacing");
    }

    function test_observe_returnsTwoCumulatives() public view {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 60;
        secondsAgos[1] = 0;
        int56[] memory cumulatives = adapter.observe(POOL, secondsAgos);
        assertEq(cumulatives.length, 2, "expected 2 tick cumulatives");
        // current cumulative (index 1) >= older one (index 0) for positive tick
        console.logInt(cumulatives[0]);
        console.logInt(cumulatives[1]);
    }

    function test_mint_approvesAndMintsPosition() public {
        uint256 amt0 = 1e18;
        uint256 amt1 = 1e4;

        deal(TOKEN0, address(this), amt0);
        deal(TOKEN1, address(this), amt1);
        IERC20(TOKEN0).approve(address(adapter), amt0);
        IERC20(TOKEN1).approve(address(adapter), amt1);

        vm.mockCall(TOKEN1, abi.encodeWithSelector(IERC20.approve.selector, POS_MGR, uint256(0)), abi.encode(true));
        vm.mockCall(TOKEN1, abi.encodeWithSelector(IERC20.approve.selector, POS_MGR, amt1), abi.encode(true));
        // Mock TOKEN1 transferFrom so the position manager can pull token1.
        vm.mockCall(TOKEN1, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));

        (uint256 tokenId, uint128 liquidity, , ) = adapter.mint(
            IDexAdapter.MintArgs({
                positionManager: POS_MGR,
                token0: TOKEN0,
                token1: TOKEN1,
                tickSpacing: TICK_SPACING,
                tickLower: TICK_LO,
                tickUpper: TICK_HI,
                amount0Desired: amt0,
                amount1Desired: amt1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 300
            })
        );

        assertGt(tokenId, 0, "tokenId must be non-zero");
        assertGt(liquidity, 0, "liquidity must be non-zero");
        assertEq(INonfungiblePositionManager(POS_MGR).ownerOf(tokenId), address(this));
        console.log("minted tokenId:", tokenId);
    }

    // ── positions: read back a minted position ───────────────────────────────

    function test_positions_returnsCorrectTicks() public {
        uint256 tokenId = _mintPosition();

        (int24 lo, int24 hi, uint128 liq, , , address t0, address t1) =
            adapter.positions(POS_MGR, tokenId);

        assertEq(lo, TICK_LO, "wrong tickLower");
        assertEq(hi, TICK_HI, "wrong tickUpper");
        assertGt(liq, 0, "zero liquidity");
        assertEq(t0, TOKEN0, "wrong token0");
        assertEq(t1, TOKEN1, "wrong token1");
    }

    // ── decreaseLiquidity ────────────────────────────────────────────────────

    function test_decreaseLiquidity_reducesLiquidity() public {
        uint256 tokenId = _mintPosition();

        (, , uint128 liqBefore, , , , ) = adapter.positions(POS_MGR, tokenId);

        // Mock TOKEN1 transfer out (pool sending token1 to this contract).
        vm.mockCall(TOKEN1, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));

        adapter.decreaseLiquidity(IDexAdapter.DecreaseArgs({
            positionManager: POS_MGR,
            tokenId: tokenId,
            liquidity: liqBefore,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 300
        }));

        (, , uint128 liqAfter, , , , ) = adapter.positions(POS_MGR, tokenId);
        assertEq(liqAfter, 0, "liquidity should be zero after full decrease");
    }

    // ── collect ──────────────────────────────────────────────────────────────

    function test_collect_sendsTokensToRecipient() public {
        uint256 tokenId = _mintPosition();

        // Remove all liquidity first so tokensOwed > 0.
        (, , uint128 liq, , , , ) = adapter.positions(POS_MGR, tokenId);
        vm.mockCall(TOKEN1, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        adapter.decreaseLiquidity(IDexAdapter.DecreaseArgs({
            positionManager: POS_MGR,
            tokenId: tokenId,
            liquidity: liq,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 300
        }));

        uint256 pre0 = IERC20(TOKEN0).balanceOf(address(this));

        (uint256 a0, ) = adapter.collect(IDexAdapter.CollectArgs({
            positionManager: POS_MGR,
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        }));

        assertGt(IERC20(TOKEN0).balanceOf(address(this)), pre0, "should have received token0");
        assertGt(a0, 0, "collected amount0 must be > 0");
    }

    // ── burn ─────────────────────────────────────────────────────────────────

    function test_burn_removesPosition() public {
        uint256 tokenId = _mintPosition();

        // Fully remove liquidity and collect before burning.
        (, , uint128 liq, , , , ) = adapter.positions(POS_MGR, tokenId);
        vm.mockCall(TOKEN1, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        adapter.decreaseLiquidity(IDexAdapter.DecreaseArgs({
            positionManager: POS_MGR,
            tokenId: tokenId,
            liquidity: liq,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 300
        }));
        adapter.collect(IDexAdapter.CollectArgs({
            positionManager: POS_MGR,
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        }));

        adapter.burn(POS_MGR, tokenId);

        vm.expectRevert();
        INonfungiblePositionManager(POS_MGR).ownerOf(tokenId);
    }

    // ── exactInputSingle: revert guards ──────────────────────────────────────

    function test_exactInputSingle_revertsAfterDeadline() public {
        deal(TOKEN0, address(this), 1e18);
        IERC20(TOKEN0).approve(address(adapter), 1e18);

        vm.expectRevert();
        adapter.exactInputSingle(IDexAdapter.SwapArgs({
            router: ROUTER,
            tokenIn: TOKEN0,
            tokenOut: TOKEN1,
            tickSpacing: TICK_SPACING,
            recipient: address(this),
            deadline: block.timestamp - 1,
            amountIn: 1e18,
            amountOutMinimum: 0
        }));
    }

    function test_exactInputSingle_revertsIfMinOutNotMet() public {
        deal(TOKEN0, address(this), 1e18);
        IERC20(TOKEN0).approve(address(adapter), 1e18);

        vm.expectRevert();
        adapter.exactInputSingle(IDexAdapter.SwapArgs({
            router: ROUTER,
            tokenIn: TOKEN0,
            tokenOut: TOKEN1,
            tickSpacing: TICK_SPACING,
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: 1e18,
            amountOutMinimum: type(uint256).max
        }));
    }

    // ── Internal helper ──────────────────────────────────────────────────────

    function _mintPosition() internal returns (uint256 tokenId) {
        uint256 amt0 = 1e18;
        uint256 amt1 = 1e4;
        deal(TOKEN0, address(this), amt0);
        deal(TOKEN1, address(this), amt1);
        IERC20(TOKEN0).approve(address(adapter), amt0);
        IERC20(TOKEN1).approve(address(adapter), amt1);
        vm.mockCall(TOKEN1, abi.encodeWithSelector(IERC20.approve.selector, POS_MGR, uint256(0)), abi.encode(true));
        vm.mockCall(TOKEN1, abi.encodeWithSelector(IERC20.approve.selector, POS_MGR, amt1), abi.encode(true));
        vm.mockCall(TOKEN1, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));

        (tokenId, , , ) = adapter.mint(IDexAdapter.MintArgs({
            positionManager: POS_MGR,
            token0: TOKEN0,
            token1: TOKEN1,
            tickSpacing: TICK_SPACING,
            tickLower: TICK_LO,
            tickUpper: TICK_HI,
            amount0Desired: amt0,
            amount1Desired: amt1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 300
        }));
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
