// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import "../../src/RebalancerVault.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockCLPool.sol";
import "../mocks/MockPositionManager.sol";
import "../mocks/MockCLSwapRouter.sol";

/// @title VaultHandler
/// @notice Single shared handler managing N actors for RebalancerVault invariant testing.
contract VaultHandler is CommonBase, StdCheats, StdUtils {
    // ─── Infrastructure references ────────────────────────────────────────────

    RebalancerVault public immutable vault;
    MockCLPool public immutable pool;
    MockERC20 public immutable token0;
    MockERC20 public immutable token1;
    address public immutable vaultOwner;
    address public immutable vaultOperator;

    /// @dev These point to the addresses used by the vault (via vm.etch in setUp).
    MockPositionManager internal immutable pm;
    MockCLSwapRouter internal immutable swapRouter;

    // ─── Actor management ─────────────────────────────────────────────────────

    address[] public actors;
    address internal _currentActor;

    uint256 internal constant REFILL_THRESHOLD_0 = 1e6; 
    uint256 internal constant REFILL_AMOUNT_0 = 100e8;
    uint256 internal constant REFILL_THRESHOLD_1 = 1e18; 
    uint256 internal constant REFILL_AMOUNT_1 = 1e25; 

    /// @dev Mirrors vault.balanceOf(actor). Updated only on confirmed mints/burns.
    mapping(address => uint256) public ghostShares;

    /// @dev Sticky flag: set true if any rebalance call mutated a share balance or
    bool public ghostRebalanceViolated;

    /// @dev Sticky flag: set true if compoundFees reduced totalAssets without a
    bool public ghostCompoundViolated;

    uint256 public depositCalls;
    uint256 public depositToken1Calls;
    uint256 public redeemCalls;
    uint256 public rebalanceCalls;
    uint256 public compoundCalls;
    uint256 public priceMoveCalls;

    uint256 public depositReverts;
    uint256 public depositToken1Reverts;
    uint256 public redeemReverts;
    uint256 public rebalanceReverts;
    uint256 public compoundReverts;

    int24 internal constant TICK_SPACING = 200;
    int24 internal constant TICK_BASE = 345_397;
    int24 internal constant TICK_FUZZ_MIN = 245_400;
    int24 internal constant TICK_FUZZ_MAX = 445_400;

    uint256 internal constant DEAD_SHARES = 1_000;

    /// @dev Selects actor from actors[], refills tokens if low, applies vm.prank.
    modifier useActor(uint256 seed) {
        _currentActor = actors[bound(seed, 0, actors.length - 1)];
        _refillActor(_currentActor);
        vm.startPrank(_currentActor);
        _;
        vm.stopPrank();
    }

    constructor(
        RebalancerVault _vault,
        MockCLPool _pool,
        MockERC20 _token0,
        MockERC20 _token1,
        address _owner,
        address _operator,
        address[] memory _actors
    ) {
        vault = _vault;
        pool = _pool;
        token0 = _token0;
        token1 = _token1;
        vaultOwner = _owner;
        vaultOperator = _operator;

        pm = MockPositionManager(address(_vault.positionManager()));
        swapRouter = MockCLSwapRouter(address(_vault.clSwapRouter()));

        for (uint256 i = 0; i < _actors.length; i++) {
            actors.push(_actors[i]);
            _token0.mint(_actors[i], REFILL_AMOUNT_0);
            _token1.mint(_actors[i], REFILL_AMOUNT_1);
            vm.startPrank(_actors[i]);
            _token0.approve(address(_vault), type(uint256).max);
            _token1.approve(address(_vault), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _refillActor(address actor) internal {
        if (token0.balanceOf(actor) < REFILL_THRESHOLD_0) {
            token0.mint(actor, REFILL_AMOUNT_0);
        }
        if (token1.balanceOf(actor) < REFILL_THRESHOLD_1) {
            token1.mint(actor, REFILL_AMOUNT_1);
        }
    }

    /// @notice Fuzz ERC-4626 token0 deposits.
    function deposit(
        uint256 actorSeed,
        uint256 assets
    ) external useActor(actorSeed) {
        depositCalls++;
        
        if (vault.paused()) return;

        uint256 supply = vault.totalSupply();
        uint256 ta = vault.totalAssets();

        if (supply > 0 && ta == 0) return;

        uint256 balance0 = token0.balanceOf(_currentActor);
        if (balance0 == 0) return;

        uint256 minDeposit = (supply == 0) ? DEAD_SHARES + 1 : 1;
        if (balance0 < minDeposit) return;

        assets = bound(assets, minDeposit, balance0);

        if (vault.previewDeposit(assets) == 0) return;

        try vault.deposit(assets, _currentActor) returns (uint256 shares) {
            ghostShares[_currentActor] += shares;
        } catch {
            depositReverts++;
        }
    }

    // ─── Handler: depositToken1 ───────────────────────────────────────────────

    /// @notice Fuzz token1 deposits. previewDepositToken1 gates the call to avoid

    function depositToken1(
        uint256 actorSeed,
        uint256 amount
    ) external useActor(actorSeed) {
        depositToken1Calls++;

        if (vault.paused()) return;

        uint256 supply = vault.totalSupply();
        uint256 ta = vault.totalAssets();

        if (supply > 0 && ta == 0) return;

        uint256 balance1 = token1.balanceOf(_currentActor);
        if (balance1 == 0) return;

        amount = bound(amount, 1, balance1);

        // The vault's own preview function is the authoritative guard
        if (vault.previewDepositToken1(amount) == 0) return;

        try vault.depositToken1(amount, _currentActor) returns (
            uint256 shares
        ) {
            ghostShares[_currentActor] += shares;
        } catch {
            depositToken1Reverts++;
        }
    }

    // ─── Handler: redeem ──────────────────────────────────────────────────────

    /// @notice Fuzz share redemptions. Redeems a random percentage of the actor's
    function redeem(
        uint256 actorSeed,
        uint256 sharesPct
    ) external useActor(actorSeed) {
        redeemCalls++;

        if (vault.paused()) return;

        uint256 shares = vault.balanceOf(_currentActor);
        if (shares == 0) return;

        uint256 maxR = vault.maxRedeem(_currentActor);
        if (maxR == 0) return;

        sharesPct = bound(sharesPct, 1, 100);
        uint256 toRedeem = bound((shares * sharesPct) / 100, 1, maxR);

        // Vault reverts if redeemed assets would be 0 (zero-value round-down)
        if (vault.previewRedeem(toRedeem) == 0) return;

        try vault.redeem(toRedeem, _currentActor, _currentActor) returns (
            uint256
        ) {
            // Shares burned; mirror in ghost
            ghostShares[_currentActor] -= toRedeem;
        } catch {
            redeemReverts++;
        }
    }

    // ─── Handler: rebalance ───────────────────────────────────────────────────

    /// @notice Fuzz the vault's core strategy operation: LP position removal,

    function rebalance(uint256 swapSeed, uint256 swapAmountSeed) external {
        rebalanceCalls++;

        if (vault.paused()) return;
        if (vault.tokenId() == 0) return; // no active position to rebalance

        // ── Snapshot shares before call ────────────────────────────────────
        uint256 supplyBefore = vault.totalSupply();
        uint256[] memory balsBefore = new uint256[](actors.length);
        for (uint256 i = 0; i < actors.length; i++) {
            balsBefore[i] = vault.balanceOf(actors[i]);
        }

        // ── Bound swap parameters ──────────────────────────────────────────
        bool swapZeroForOne = (swapSeed % 2 == 0);
        uint256 idleBal = swapZeroForOne
            ? token0.balanceOf(address(vault))
            : token1.balanceOf(address(vault));

        // Bound to ≤ 50% of idle to ensure reminting is always viable
        uint256 swapAmount = (idleBal > 0)
            ? bound(swapAmountSeed, 0, idleBal / 2)
            : 0;

        vm.prank(vaultOperator);
        try vault.rebalance(swapZeroForOne, swapAmount, RebalancerVault.StrategyType.MEDIUM) {
            if (vault.totalSupply() != supplyBefore) {
                ghostRebalanceViolated = true;
            }
            for (uint256 i = 0; i < actors.length; i++) {
                if (vault.balanceOf(actors[i]) != balsBefore[i]) {
                    ghostRebalanceViolated = true;
                }
            }
        } catch {
            rebalanceReverts++;
        }
    }

    // ─── Handler: compoundFees ────────────────────────────────────────────────

    /// @notice Fuzz fee collection. Optionally injects simulated LP fees before

    function compoundFees(uint256 feeSeed) external {
        compoundCalls++;

        if (vault.paused()) return;
        if (vault.tokenId() == 0) return;

        // Optionally simulate pending LP fees for 2/3 of calls
        if (feeSeed % 3 != 0) {
            uint256 fee0 = bound(feeSeed, 0, 1e5); // ≤ 0.001 BTC
            uint256 fee1 = bound(feeSeed >> 128, 0, 1e14); // small MUSD amount
            if (fee0 > 0 || fee1 > 0) {
                // Ensure PM can cover the payouts
                if (fee0 > 0) token0.mint(address(pm), fee0);
                if (fee1 > 0) token1.mint(address(pm), fee1);
                pm.setPendingFees(vault.tokenId(), fee0, fee1);
            }
        }

        uint256 taBefore = vault.totalAssets();

        vm.prank(vaultOperator);
        try vault.collectFees(0, 0) {
            if (
                vault.performanceFeeBps() == 0 && vault.totalAssets() < taBefore
            ) {
                ghostCompoundViolated = true;
            }
        } catch {
            compoundReverts++;
        }
    }

    function movePrice(uint256 tickSeed) external {
        priceMoveCalls++;

        int24 newTick = int24(
            int256(
                bound(
                    tickSeed,
                    uint256(int256(TICK_FUZZ_MIN)),
                    uint256(int256(TICK_FUZZ_MAX))
                )
            )
        );
        // Floor-align to tick spacing
        newTick = (newTick / TICK_SPACING) * TICK_SPACING;

        uint160 newSqrtPrice = TickMath.getSqrtRatioAtTick(newTick);
        pool.setPrice(newSqrtPrice, newTick);
    }

    // ─── View helpers (used by InvariantTest) ─────────────────────────────────

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    /// @dev Sum of vault.balanceOf for all actors + dead-shares address.
    ///      Invariant A uses this to check totalSupply == sum of known balances.
    function sumActualBalances() external view returns (uint256 total) {
        total = vault.balanceOf(address(0xdead));
        for (uint256 i = 0; i < actors.length; i++) {
            total += vault.balanceOf(actors[i]);
        }
    }

    /// @dev Sum of all ghost share entries.
    function sumGhostShares() external view returns (uint256 total) {
        for (uint256 i = 0; i < actors.length; i++) {
            total += ghostShares[actors[i]];
        }
    }
}
