// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {Actor} from "./Actor.sol";
import {Clamp} from "./utils/Clamp.sol";
import {DecimalPrinter} from "./utils/DecimalPrinter.sol";
import {Deployer} from "./utils/Deployer.sol";
import {vm} from "./utils/Hevm.sol";
import {Logger} from "./utils/Logger.sol";
import {Math} from "./utils/Math.sol";
import {StringUtils} from "./utils/StringUtils.sol";
import {EnumerableSet} from "./utils/EnumerableSet.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {RebalancerVaultUpgradeable} from "../../src/RebalancerVaultUpgradeable.sol";
import {Strategy} from "../../src/strategies/Strategy.sol";
import {CLDexAdapter} from "../../src/adapters/CLDexAdapter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockCLPool} from "../mocks/MockCLPool.sol";
import {MockPositionManager} from "../mocks/MockPositionManager.sol";
import {MockCLSwapRouter} from "../mocks/MockCLSwapRouter.sol";

/// @notice Base contract with state variables and setup functions
abstract contract Base is StringUtils, Clamp, Deployer, Math {
    using DecimalPrinter for uint256;

    string[] internal ACTOR_LABELS = ["Alice", "Bob", "Charlie"];
    uint256 internal constant BLOCK_INTERVAL = 12 seconds;
    uint256 internal constant INITIAL_ETH_BALANCE = 1_000 ether;

    // token0 = MUSD (18dec) = the ERC-4626 asset; token1 = BTC (8dec).
    uint256 internal constant INITIAL_TOKEN0_BALANCE = 1_000_000e18; // 1M MUSD
    uint256 internal constant INITIAL_TOKEN1_BALANCE = 1_000e8;      // 1000 BTC

    // ―――――――――――――――――――――――― Pool constants ―――――――――――――――――――――――――
    // token0=MUSD(18dec), token1=BTC(8dec), price=100k MUSD/BTC → tick = -345_397
    uint160 internal constant SQRT_PRICE_100K = 2_506_420_941_470_528_471_776;
    int24 internal constant TICK_100K = -345_397;
    int24 internal constant TICK_SPACING = 200;
    uint256 internal constant DEAD_SHARES = 1_000;

    // Position range used to seed the initial CL position.
    int24 internal POS_LO;
    int24 internal POS_HI;

    // Seed amounts used to bring the vault into "position exists" state.
    uint256 internal constant SEED_DEPOSIT = 100_000e18; // MUSD deposited by admin
    uint256 internal constant SEED_POSITION_AMOUNT0 = 50_000e18;

    // ―――――――――――――――――――――――――― Ghosts ――――――――――――――――――――――――――

    struct Ghosts {
        uint256 _placeholder;
    }

    Ghosts internal ghosts;

    // ―――――――――――――――――――――――――― Actors ――――――――――――――――――――――――――

    address[] internal actors;
    address internal actor;
    address internal admin;

    modifier asActor() virtual {
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }

    modifier asAdmin() virtual {
        vm.startPrank(admin);
        _;
        vm.stopPrank();
    }

    // ―――――――――――――――――――――――― Contracts ―――――――――――――――――――――――――

    MockERC20 internal token0;   // MUSD, 18 decimals — the ERC4626 asset
    MockERC20 internal token1;   // BTC, 8 decimals
    MockCLPool internal pool;
    MockPositionManager internal pm;
    MockCLSwapRouter internal router;
    Strategy internal strategy;
    CLDexAdapter internal adapter;
    UpgradeableBeacon internal beacon;
    RebalancerVaultUpgradeable internal vault;

    address internal feeRecipient;

    // ―――――――――――――――――――――――――― Setup ―――――――――――――――――――――――――――

    function setup() internal {
        // Establish a large timestamp floor so pool.observe() never underflows
        // (it computes block.timestamp - twapSeconds with twapSeconds >= 60).
        vm.warp(1_000_000);
        vm.roll(1_000);

        feeRecipient = address(0xFEE);

        // --- Tokens ---
        token0 = new MockERC20("Mezo USD", "MUSD", 18);
        token1 = new MockERC20("Bitcoin", "BTC", 8);

        // --- Pool ---
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

        // --- Position manager + router ---
        pm = new MockPositionManager();
        router = new MockCLSwapRouter();
        pm.setMintReturn(1e18, 0, 0);
        // Reserves so decrease/collect/swap can pay out.
        token0.mint(address(pm), 10_000_000e18);
        token1.mint(address(pm), 1_000_000e8);
        token0.mint(address(router), 10_000_000e18);
        token1.mint(address(router), 1_000_000e8);

        // --- Strategy + adapter ---
        strategy = new Strategy(700);
        adapter = new CLDexAdapter();

        // --- Vault (beacon proxy) ---
        // owner == operator == guardian == address(this) so operator/admin
        // handlers can call directly; only user flows prank as the actors.
        RebalancerVaultUpgradeable impl = new RebalancerVaultUpgradeable();
        beacon = new UpgradeableBeacon(address(impl), address(this));

        bytes memory initData = abi.encodeCall(
            RebalancerVaultUpgradeable.initialize,
            (
                RebalancerVaultUpgradeable.InitParams({
                    owner: address(this),
                    operator: address(this),
                    guardian: address(this),
                    pool: address(pool),
                    positionManager: address(pm),
                    swapRouter: address(router),
                    strategy: address(strategy),
                    dexAdapter: address(adapter),
                    feeRecipient: feeRecipient,
                    name: "Rebalancer BTC/MUSD",
                    symbol: "rbBTC"
                })
            )
        );
        vault = RebalancerVaultUpgradeable(
            payable(address(new BeaconProxy(address(beacon), initData)))
        );

        // Aligned position range around the TWAP tick.
        POS_LO = ((TICK_100K - 2000) / TICK_SPACING) * TICK_SPACING;
        POS_HI = ((TICK_100K + 2000) / TICK_SPACING) * TICK_SPACING;

        setupActors();

        // Seed the vault: admin (address(this)) makes the first deposit and
        // initializes the CL position so tokenId != 0 and rebalance/collectFees
        // are reachable by the fuzzer.
        token0.mint(address(this), SEED_DEPOSIT);
        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
        vault.deposit(SEED_DEPOSIT, address(this));
        vault.initializePosition(POS_LO, POS_HI, SEED_POSITION_AMOUNT0, 0, 0, 0);

        // Advance so seeded deposit's same-block guard does not bleed into fuzzing.
        vm.roll(block.number + 1);
    }

    function setupActors() internal {
        admin = address(this);
        vm.label(admin, "Admin");

        for (uint256 i; i < ACTOR_LABELS.length; i++) {
            address _actor = address(new Actor{value: INITIAL_ETH_BALANCE}());
            actors.push(_actor);
            if (ACTOR_LABELS.length > i) {
                vm.label(_actor, ACTOR_LABELS[i]);
            }
            // Fund and approve each actor for both tokens.
            token0.mint(_actor, INITIAL_TOKEN0_BALANCE);
            token1.mint(_actor, INITIAL_TOKEN1_BALANCE);
            vm.startPrank(_actor);
            token0.approve(address(vault), type(uint256).max);
            token1.approve(address(vault), type(uint256).max);
            vm.stopPrank();
        }
        actor = actors[0];
    }

    // ――――――――――――――――――――――――― Helpers ――――――――――――――――――――――――――

    // Maps an arbitrary address to an actor address
    function toActor(address addy) internal view returns (address) {
        return actors[uint256(uint160(addy)) % actors.length];
    }

    // Maps an arbitrary address to an actor address that is different from the current actor
    function toActorNotCurrent(address addy) internal view returns (address) {
        address _actor = actors[uint256(uint160(addy)) % actors.length];
        if (_actor == actor) {
            _actor = actors[(uint256(uint160(addy)) + 1) % actors.length];
        }
        return _actor;
    }

    // Sums the native token balances of all actors
    function sumActorsBalances() internal view returns (uint256 sumOfBalances) {
        for (uint256 i; i < actors.length; i++) {
            sumOfBalances += actors[i].balance;
        }
    }

    // Sums the ERC-20 token balances of all actors for a given token
    function sumActorsERC20Balances(address _token) internal view returns (uint256 sumOfBalances) {
        for (uint256 i; i < actors.length; i++) {
            bytes memory data = abi.encodeWithSignature("balanceOf(address)", actors[i]);
            (bool success, bytes memory result) = _token.staticcall(data);
            require(success, "sumActorsERC20Balances: failed to get balance");
            sumOfBalances += abi.decode(result, (uint256));
        }
    }

    function skipBlocks(uint256 blocks) internal {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * BLOCK_INTERVAL);
    }

    function skipTime(uint256 time) internal {
        uint256 blocks = (time + BLOCK_INTERVAL - 1) / BLOCK_INTERVAL;
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + time);
    }
}
