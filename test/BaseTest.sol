// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/RebalancerVault.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockCLPool.sol";
import "./mocks/MockPositionManager.sol";
import "./mocks/MockCLSwapRouter.sol";

abstract contract BaseTest is Test {
    // ── Actors ───────────────────────────────────────────────────────────────
    address internal owner = makeAddr("owner");
    address internal operator = makeAddr("operator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal feeRecip = makeAddr("feeRecipient");

    // ── Contracts ────────────────────────────────────────────────────────────
    MockERC20 internal token0; // BTC-like,  8 decimals
    MockERC20 internal token1; // MUSD-like, 18 decimals
    MockCLPool internal pool;
    MockPositionManager internal pm;
    MockCLSwapRouter internal router;
    RebalancerVault public vault;

    uint160 internal constant SQRT_PRICE_100K =
        2_505_414_483_750_479_251_915_866_636;
    int24 internal constant TICK_100K = 345_397; // log(1e15)/log(1.0001)
    int24 internal constant TICK_SPACING = 200;

    uint256 public constant DEAD_SHARES = 1_000;
    uint256 internal constant INITIAL_DEPOSIT = 1e8;

    // ── Setup ────────────────────────────────────────────────────────────────
    function setUp() public virtual {
        // Ensure block.timestamp > twapSeconds (300) so observe() subtraction doesn't underflow.
        vm.warp(10_000);

        token0 = new MockERC20("Bitcoin", "BTC", 8);
        token1 = new MockERC20("Mezo USD", "MUSD", 18);

        pool = new MockCLPool();

        pool.initialize(
            address(0),
            address(token0),
            address(token1),
            TICK_SPACING,
            address(0),
            SQRT_PRICE_100K
        );

        pool.setPrice(SQRT_PRICE_100K, TICK_100K);

        pm = new MockPositionManager();
        router = new MockCLSwapRouter();

        vault = new RebalancerVault(
            owner,
            address(pool),
            operator,
            "Rebalancer BTC/MUSD",
            "rbBTC"
        );

        vm.etch(address(vault.positionManager()), address(pm).code);

        vm.etch(address(vault.clSwapRouter()), address(router).code);

        _fundActors();

        _approveAll();
    }

    // ── Internal setup helpers ────────────────────────────────────────────────

    function _fundActors() internal {
        uint256 btc = 100e8;
        uint256 musd = 1e25;

        token0.mint(alice, btc);
        token0.mint(bob, btc);
        token0.mint(carol, btc);
        token0.mint(owner, btc);

        token1.mint(alice, musd);
        token1.mint(bob, musd);
        token1.mint(carol, musd);
        token1.mint(owner, musd);

        token0.mint(address(pm), 100e8);
        token1.mint(address(pm), 1e25);
        token0.mint(address(router), 100e8);
        token1.mint(address(router), 1e25);
    }

    function _approveAll() internal {
        address[4] memory actors = [alice, bob, carol, owner];
        for (uint i = 0; i < actors.length; i++) {
            vm.startPrank(actors[i]);
            token0.approve(address(vault), type(uint256).max);
            token1.approve(address(vault), type(uint256).max);
            vm.stopPrank();
        }
    }

    // ── Test helpers ──────────────────────────────────────────────────────────

    /// @dev Seeds vault with dead shares via alice's first deposit.
    ///      Advances one block so subsequent withdraw/redeem can pass the same-block guard.
    function _initialDeposit(uint256 assets) internal returns (uint256 shares) {
        vm.prank(alice);
        shares = vault.deposit(assets, alice);
        vm.roll(block.number + 1);
    }

    /// @dev Initializes an LP position in the vault (owner only).
    function _initPosition(
        int24 tickLower,
        int24 tickUpper,
        uint256 amt0,
        uint256 amt1
    ) internal {
        vm.startPrank(owner);
        token0.transfer(address(vault), amt0);
        token1.transfer(address(vault), amt1);
        vault.initializePosition(tickLower, tickUpper, amt0, amt1, 0, 0);
        vm.stopPrank();
    }

    /// @dev Returns a tick range aligned to TICK_SPACING around TICK_100K.
    function _defaultRange() internal pure returns (int24 lo, int24 hi) {
        lo = ((TICK_100K - 2000) / TICK_SPACING) * TICK_SPACING;
        hi = ((TICK_100K + 2000) / TICK_SPACING) * TICK_SPACING;
    }

    /// @dev Warps past the 2-day fee timelock.
    function _warpPastTimelock() internal {
        vm.warp(block.timestamp + 3 days);
    }

    /// @dev Proposes and applies a performance fee in one call.
    function _setFee(uint256 bps) internal {
        vm.startPrank(owner);
        vault.proposePerformanceFee(bps, feeRecip);
        _warpPastTimelock();
        vault.applyPerformanceFee();
        vm.stopPrank();
    }

    /// @dev Simulate price movement on the mock pool.
    function _setPoolPrice(uint160 sqrtPriceX96, int24 tick) internal {
        pool.setPrice(sqrtPriceX96, tick);
    }
}
