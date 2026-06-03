// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {
    RebalancerVaultUpgradeable
} from "../src/RebalancerVaultUpgradeable.sol";
import {Strategy} from "../src/strategies/Strategy.sol";
import {CLDexAdapter} from "../src/adapters/CLDexAdapter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockCLPool} from "./mocks/MockCLPool.sol";
import {MockPositionManager} from "./mocks/MockPositionManager.sol";
import {MockCLSwapRouter} from "./mocks/MockCLSwapRouter.sol";

abstract contract BaseTest is Test {
    address internal owner = makeAddr("owner");
    address internal operator = makeAddr("operator");
    address internal guardian = makeAddr("guardian");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal feeRecip = makeAddr("feeRecipient");

    MockERC20 internal token0;
    MockERC20 internal token1;
    MockCLPool internal pool;
    MockPositionManager internal pm;
    MockCLSwapRouter internal router;

    UpgradeableBeacon internal beacon;
    RebalancerVaultUpgradeable internal vault;
    Strategy internal strategy;
    CLDexAdapter internal adapter;

    address internal constant PM_ADDR =
        address(0x00000000000000000000000000000000000000A1);
    address internal constant ROUTER_ADDR =
        address(0x00000000000000000000000000000000000000A2);

    // token0=MUSD(18dec), token1=BTC(8dec), price=100k MUSD/BTC
    // P_raw = BTC-wei/MUSD-wei = 1e-15  →  tick = -345_397
    uint160 internal constant SQRT_PRICE_100K = 2_506_420_941_470_528_471_776;
    int24 internal constant TICK_100K = -345_397;
    int24 internal constant TICK_SPACING = 200;
    uint256 public constant DEAD_SHARES = 1_000;

    function setUp() public virtual {
        vm.warp(10_000);

        token0 = new MockERC20("Mezo USD", "MUSD", 18);
        token1 = new MockERC20("Bitcoin", "BTC", 8);

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
        vm.etch(PM_ADDR, address(pm).code);
        vm.etch(ROUTER_ADDR, address(router).code);

        strategy = new Strategy(700);
        adapter = new CLDexAdapter();

        RebalancerVaultUpgradeable impl = new RebalancerVaultUpgradeable();
        beacon = new UpgradeableBeacon(address(impl), address(this));

        bytes memory initData = abi.encodeCall(
            RebalancerVaultUpgradeable.initialize,
            (
                RebalancerVaultUpgradeable.InitParams({
                    owner: owner,
                    operator: operator,
                    guardian: guardian,
                    pool: address(pool),
                    positionManager: PM_ADDR,
                    swapRouter: ROUTER_ADDR,
                    strategy: address(strategy),
                    dexAdapter: address(adapter),
                    feeRecipient: owner,
                    name: "Rebalancer BTC/MUSD",
                    symbol: "rbBTC"
                })
            )
        );
        vault = RebalancerVaultUpgradeable(
            payable(address(new BeaconProxy(address(beacon), initData)))
        );

        vm.store(PM_ADDR, bytes32(0), bytes32(uint256(1)));
        MockPositionManager(PM_ADDR).setMintReturn(1e18, 0, 0);
        token0.mint(PM_ADDR, 1_000_000e18); // MUSD
        token1.mint(PM_ADDR, 100_000e8); // BTC (large reserve for liquidity returns)
        token0.mint(ROUTER_ADDR, 1_000_000e18);
        token1.mint(ROUTER_ADDR, 100_000e8);

        _fundActors();
        _approveAll();
    }

    function _fundActors() internal {
        address[4] memory a = [alice, bob, carol, owner];
        for (uint i; i < a.length; i++) {
            token0.mint(a[i], 1_000_000e18); // 1M MUSD
            token1.mint(a[i], 1_000e8); // 1000 BTC
        }
    }

    function _approveAll() internal {
        address[4] memory a = [alice, bob, carol, owner];
        for (uint i; i < a.length; i++) {
            vm.startPrank(a[i]);
            token0.approve(address(vault), type(uint256).max);
            token1.approve(address(vault), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _initialDeposit(uint256 assets) internal returns (uint256 shares) {
        vm.prank(alice);
        shares = vault.deposit(assets, alice);
        vm.roll(block.number + 1);
    }

    function _initPosition(
        int24 lo,
        int24 hi,
        uint256 amt0,
        uint256 amt1
    ) internal {
        vm.startPrank(owner);
        // token0.transfer(address(vault), amt0);
        // token1.transfer(address(vault), amt1);
        vault.initializePosition(lo, hi, amt0, amt1, 0, 0);
        vm.stopPrank();
    }
}
