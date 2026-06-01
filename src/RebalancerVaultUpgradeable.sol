// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC4626Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {
    ReentrancyGuardTransient
} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ICLPool} from "./interfaces/pool/ICLPool.sol";
import {
    INonfungiblePositionManager
} from "./interfaces/INonfungiblePositionManager.sol";
import {ICLSwapRouter} from "./interfaces/router/ICLSwapRouter.sol";
import {IDexAdapter} from "./interfaces/IDexAdapter.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";

import {VaultStorageLib} from "./libraries/VaultStorageLib.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
import {VaultMath} from "./libraries/VaultMath.sol";

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {
    LiquidityAmounts
} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

/// @title RebalancerVaultUpgradeable
/// @notice Beacon-proxy-upgradeable ERC4626 concentrated-liquidity vault denominated in
///         token0. Structural refactor of the monolithic RebalancerVault.sol — identical
///         external behavior, split across modules:
///           OracleLib  → TWAP math (single slot0 + observe read per call)
///           VaultMath  → slippage / optimal-swap / tick math (pure)
///           IStrategy  → range selection (staticcall; vault re-validates output)
///           IDexAdapter→ DEX I/O (reads = staticcall; writes = delegatecall in vault ctx)
/// @dev    STORAGE: all custom state lives in the ERC-7201 namespace returned by _s().
///         Every function that touches state MUST go through _s() — never bare identifiers.
///         UPGRADEABILITY: implementation constructor calls _disableInitializers(); one
///         UpgradeableBeacon per deployment; one BeaconProxy per (pool, strategy) vault.
contract RebalancerVaultUpgradeable is
    Initializable,
    ERC20Upgradeable,
    ERC4626Upgradeable,
    ReentrancyGuardTransient
{
    using SafeERC20 for IERC20;

    uint256 public constant DEAD_SHARES = 1_000;

    // ─── Events ─────────────────────────────────────────────────────────────────

    event Token1Deposited(
        address indexed sender,
        address indexed receiver,
        uint256 token1Amount,
        uint256 shares
    );
    event Rebalanced(
        uint256 indexed oldTokenId,
        uint256 indexed newTokenId,
        int24 newTickLower,
        int24 newTickUpper,
        uint128 newLiquidity
    );
    event PositionInitialized(
        uint256 indexed tokenId,
        int24 tickLower,
        int24 tickUpper
    );
    event FeesCollected(uint256 fee0, uint256 fee1, address indexed recipient);
    event OperatorUpdated(address indexed newOperator);
    event VaultPaused(bool paused);
    event PerformanceFeeUpdated(uint256 bps, address indexed recipient);
    event TokenSwept(address indexed token, address indexed to, uint256 amount);
    event PerformanceFeeProposed(
        uint256 bps,
        address indexed recipient,
        uint256 activeAt
    );
    event OwnershipTransferStarted(
        address indexed previousOwner,
        address indexed newOwner
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event StrategyProposed(address indexed strategy, uint256 activeAt);
    event StrategyUpdated(address indexed strategy);
    event DexAdapterProposed(address indexed dexAdapter, uint256 activeAt);
    event DexAdapterUpdated(address indexed dexAdapter);
    event GuardianUpdated(address indexed guardian);

    // ─── Errors ─────────────────────────────────────────────────────────────────

    error NotOwner();
    error NotOperator();
    error NotGuardian();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidToken();
    error AlreadyInitialized();
    error NotInitialized();
    error InvalidRange();
    error InvalidStrategyTicks();
    error NoLiquidityMinted();
    error BelowMinDeposit();
    error NoAssets();
    error FeeTooHigh();
    error ExceedsMaxDeposit();
    error ExceedsMaxMint();
    error ExceedsMaxWithdraw();
    error ExceedsMaxRedeem();
    error SameOwner();
    error NotPendingOwner();
    error InsufficientToken0ForWithdraw(uint256 available, uint256 required);
    error TimelockActive();
    error InvalidPoolPrice();
    error PriceDeviatedFromTwap();
    error NothingToMint();
    error SameBlock();

    // ─── Init params ────────────────────────────────────────────────────────────

    /// @notice Parameters consumed once by {initialize}. Field order is ABI-stable
    ///         (factory encodes against this struct — do not reorder).
    struct InitParams {
        address owner;
        address operator;
        address guardian;
        address pool;
        address positionManager;
        address swapRouter;
        address strategy;
        address dexAdapter;
        address feeRecipient;
        string name;
        string symbol;
    }

    // ─── Modifiers ──────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != _s().owner) revert NotOwner();
        _;
    }

    modifier onlyOperator() {
        if (msg.sender != _s().operator) revert NotOperator();
        _;
    }

    modifier whenNotPaused() {
        require(!_s().paused, "Vault: paused");
        _;
    }

    modifier positionExists() {
        if (_s().tokenId == 0) revert NotInitialized();
        _;
    }

    // ─── Constructor + initializer ───────────────────────────────────────────────

    /// @dev Prevents the implementation contract itself from being initialized.
    constructor() {
        _disableInitializers();
    }

    /// @notice One-time initializer replacing the monolith constructor.
    function initialize(InitParams calldata p) external initializer {
        if (
            p.owner == address(0) ||
            p.operator == address(0) ||
            p.guardian == address(0) ||
            p.pool == address(0) ||
            p.positionManager == address(0) ||
            p.swapRouter == address(0) ||
            p.strategy == address(0) ||
            p.dexAdapter == address(0) ||
            p.feeRecipient == address(0)
        ) revert ZeroAddress();

        __ERC20_init(p.name, p.symbol);
        __ERC4626_init(IERC20(ICLPool(p.pool).token0()));
        // ReentrancyGuardTransient uses transient storage; no __init required.

        VaultStorageLib.VaultStorage storage s = _s();

        s.owner = p.owner;
        s.operator = p.operator;
        s.guardian = p.guardian;
        s.pool = p.pool;
        s.positionManager = p.positionManager;
        s.swapRouter = p.swapRouter;
        s.strategy = p.strategy;
        s.dexAdapter = p.dexAdapter;
        s.feeRecipient = p.feeRecipient;

        address t0 = ICLPool(p.pool).token0();
        address t1 = ICLPool(p.pool).token1();
        s.token0 = t0;
        s.token1 = t1;
        s.decimals0 = _safeDecimals(t0);
        s.decimals1 = _safeDecimals(t1);

        s.performanceFeeBps = 1000;
        s.twapSeconds = 300;
        s.maxTwapDeviationTicks = 200;
        s.slippageBps = 50;
    }

    // ─── Storage accessor ────────────────────────────────────────────────────────

    function _s() internal pure returns (VaultStorageLib.VaultStorage storage) {
        return VaultStorageLib.get();
    }

    // ─── Public getters ─────────────────────────────────────────────────────────

    function owner() public view returns (address) {
        return _s().owner;
    }
    function pendingOwner() public view returns (address) {
        return _s().pendingOwner;
    }
    function operator() public view returns (address) {
        return _s().operator;
    }
    function guardian() public view returns (address) {
        return _s().guardian;
    }
    function paused() public view returns (bool) {
        return _s().paused;
    }
    function strategy() public view returns (address) {
        return _s().strategy;
    }
    function dexAdapter() public view returns (address) {
        return _s().dexAdapter;
    }
    function pendingStrategy() public view returns (address) {
        return _s().pendingStrategy;
    }
    function strategyChangeActiveAt() public view returns (uint256) {
        return _s().strategyChangeActiveAt;
    }
    function pendingDexAdapter() public view returns (address) {
        return _s().pendingDexAdapter;
    }
    function dexAdapterChangeActiveAt() public view returns (uint256) {
        return _s().dexAdapterChangeActiveAt;
    }
    function pool() public view returns (ICLPool) {
        return ICLPool(_s().pool);
    }
    function token0() public view returns (IERC20) {
        return IERC20(_s().token0);
    }
    function token1() public view returns (IERC20) {
        return IERC20(_s().token1);
    }
    function decimals0() public view returns (uint8) {
        return _s().decimals0;
    }
    function decimals1() public view returns (uint8) {
        return _s().decimals1;
    }
    function positionManager()
        public
        view
        returns (INonfungiblePositionManager)
    {
        return INonfungiblePositionManager(_s().positionManager);
    }
    function swapRouter() public view returns (ICLSwapRouter) {
        return ICLSwapRouter(_s().swapRouter);
    }
    function tokenId() public view returns (uint256) {
        return _s().tokenId;
    }
    function performanceFeeBps() public view returns (uint256) {
        return _s().performanceFeeBps;
    }
    function feeRecipient() public view returns (address) {
        return _s().feeRecipient;
    }
    function pendingFeeBps() public view returns (uint256) {
        return _s().pendingFeeBps;
    }
    function pendingFeeRecipient() public view returns (address) {
        return _s().pendingFeeRecipient;
    }
    function feeChangeActiveAt() public view returns (uint256) {
        return _s().feeChangeActiveAt;
    }
    function rebalanceCount() public view returns (uint256) {
        return _s().rebalanceCount;
    }
    function totalFees0Earned() public view returns (uint256) {
        return _s().totalFees0Earned;
    }
    function totalFees1Earned() public view returns (uint256) {
        return _s().totalFees1Earned;
    }
    function twapSeconds() public view returns (uint32) {
        return _s().twapSeconds;
    }
    function maxTwapDeviationTicks() public view returns (int24) {
        return _s().maxTwapDeviationTicks;
    }
    function slippageBps() public view returns (uint256) {
        return _s().slippageBps;
    }

    // ─── ERC4626 overrides ───────────────────────────────────────────────────────

    function decimals()
        public
        view
        override(ERC20Upgradeable, ERC4626Upgradeable)
        returns (uint8)
    {
        return _s().decimals0;
    }

    function asset() public view override returns (address) {
        return _s().token0;
    }

    function totalAssets() public view override returns (uint256) {
        return _totalVaultValueInToken0();
    }

    function convertToShares(
        uint256 assets
    ) public view override returns (uint256) {
        uint256 supply = totalSupply();
        uint256 ta = totalAssets();
        if (supply == 0) return assets;
        if (ta == 0) return 0;
        return Math.mulDiv(assets, supply, ta, Math.Rounding.Floor);
    }

    function convertToAssets(
        uint256 shares
    ) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return
            supply == 0
                ? shares
                : Math.mulDiv(
                    shares,
                    totalAssets(),
                    supply,
                    Math.Rounding.Floor
                );
    }

    function maxDeposit(address) public view override returns (uint256) {
        return _isDepositAllowed() ? type(uint256).max : 0;
    }

    function previewDeposit(
        uint256 assets
    ) public view override returns (uint256) {
        uint256 supply = totalSupply();
        uint256 ta = totalAssets();
        if (supply == 0) return assets > DEAD_SHARES ? assets - DEAD_SHARES : 0;
        if (ta == 0) return 0;
        return Math.mulDiv(assets, supply, ta, Math.Rounding.Floor);
    }

    function maxMint(address) public view override returns (uint256) {
        return _isDepositAllowed() ? type(uint256).max : 0;
    }

    function previewMint(
        uint256 shares
    ) public view override returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return shares + DEAD_SHARES;
        uint256 ta = totalAssets();
        if (ta == 0) return type(uint256).max;
        if (shares == 0) return 0;
        return Math.mulDiv(shares, ta, supply, Math.Rounding.Ceil);
    }

    function maxWithdraw(
        address owner_
    ) public view override returns (uint256) {
        if (_s().paused) return 0;
        return convertToAssets(balanceOf(owner_));
    }

    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return type(uint256).max;
        uint256 ta = totalAssets();
        if (ta == 0) return type(uint256).max;
        if (assets == 0) return 0;
        return Math.mulDiv(assets, supply, ta, Math.Rounding.Ceil);
    }

    function maxRedeem(address owner_) public view override returns (uint256) {
        return _s().paused ? 0 : balanceOf(owner_);
    }

    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    // ─── ERC4626 mutating overrides ──────────────────────────────────────────────

    /// @inheritdoc ERC4626Upgradeable
    function deposit(
        uint256 assets,
        address receiver
    ) public override whenNotPaused nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (assets > maxDeposit(receiver)) revert ExceedsMaxDeposit();
        _requireSpotNearTwap();

        VaultStorageLib.VaultStorage storage s = _s();
        s.lastDepositBlock[receiver] = block.number;

        uint256 totalValBefore = _totalVaultValueInToken0();
        uint256 supply = totalSupply();

        IERC20(s.token0).safeTransferFrom(msg.sender, address(this), assets);

        if (supply == 0) {
            if (assets <= DEAD_SHARES) revert BelowMinDeposit();
            _mint(address(0xdead), DEAD_SHARES);
            shares = assets - DEAD_SHARES;
        } else {
            if (totalValBefore == 0) revert NoAssets();
            shares = Math.mulDiv(
                assets,
                supply,
                totalValBefore,
                Math.Rounding.Floor
            );
        }

        if (shares == 0) revert ZeroAmount();
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    function mint(
        uint256 shares,
        address receiver
    ) public override whenNotPaused nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (shares > maxMint(receiver)) revert ExceedsMaxMint();
        _requireSpotNearTwap();

        VaultStorageLib.VaultStorage storage s = _s();
        s.lastDepositBlock[receiver] = block.number;

        uint256 supply = totalSupply();
        uint256 ta = totalAssets();
        if (supply > 0 && ta == 0) revert NoAssets();

        assets = previewMint(shares);
        if (assets == 0 || assets == type(uint256).max) revert ZeroAmount();

        IERC20(s.token0).safeTransferFrom(msg.sender, address(this), assets);

        if (supply == 0) _mint(address(0xdead), DEAD_SHARES);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Slippage floors are computed on-chain (TWAP + slippageBps). Keepers cannot
    ///      supply min amounts.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner_
    ) public override whenNotPaused nonReentrant returns (uint256 shares) {
        VaultStorageLib.VaultStorage storage s = _s();
        if (block.number <= s.lastDepositBlock[owner_]) revert SameBlock();
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (assets > maxWithdraw(owner_)) revert ExceedsMaxWithdraw();
        _requireSpotNearTwap();

        shares = previewWithdraw(assets);
        if (shares == 0 || shares == type(uint256).max) revert ZeroAmount();

        if (msg.sender != owner_) _spendAllowance(owner_, msg.sender, shares);

        uint256 supply = totalSupply();
        (uint256 min0, uint256 min1) = _computeRemoveSlippage(shares, supply);
        _removeProportionalLiquidity(shares, supply, min0, min1);
        _burn(owner_, shares);

        uint256 idle0 = IERC20(s.token0).balanceOf(address(this));
        if (idle0 < assets) {
            uint256 shortfall = assets - idle0;
            uint256 token1Needed = VaultMath.token0ToToken1(
                shortfall,
                OracleLib.getTwapSqrtPrice(s.pool, s.twapSeconds)
            );
            uint256 available1 = IERC20(s.token1).balanceOf(address(this));
            if (token1Needed > available1) token1Needed = available1;
            if (token1Needed > 0) {
                uint256 swapMin = VaultMath.computeSwapMinOut(
                    token1Needed,
                    false,
                    OracleLib.getTwapSqrtPrice(s.pool, s.twapSeconds),
                    s.slippageBps
                );
                _executeSwap(false, token1Needed, swapMin);
            }
        }

        uint256 finalIdle0 = IERC20(s.token0).balanceOf(address(this));
        if (finalIdle0 < assets)
            revert InsufficientToken0ForWithdraw(finalIdle0, assets);

        IERC20(s.token0).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    function redeem(
        uint256 shares,
        address receiver,
        address owner_
    ) public override whenNotPaused nonReentrant returns (uint256 assets) {
        VaultStorageLib.VaultStorage storage s = _s();
        if (block.number <= s.lastDepositBlock[owner_]) revert SameBlock();
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (shares > maxRedeem(owner_)) revert ExceedsMaxRedeem();
        _requireSpotNearTwap();

        if (msg.sender != owner_) _spendAllowance(owner_, msg.sender, shares);

        uint256 supply = totalSupply();

        uint256 idleBefore0 = IERC20(s.token0).balanceOf(address(this));
        uint256 idleBefore1 = IERC20(s.token1).balanceOf(address(this));

        (uint256 min0, uint256 min1) = _computeRemoveSlippage(shares, supply);
        _removeProportionalLiquidity(shares, supply, min0, min1);

        uint256 freed0 = IERC20(s.token0).balanceOf(address(this)) -
            idleBefore0;
        uint256 freed1 = IERC20(s.token1).balanceOf(address(this)) -
            idleBefore1;

        uint256 idleShare0 = Math.mulDiv(
            idleBefore0,
            shares,
            supply,
            Math.Rounding.Floor
        );
        uint256 idleShare1 = Math.mulDiv(
            idleBefore1,
            shares,
            supply,
            Math.Rounding.Floor
        );

        uint256 amount0 = freed0 + idleShare0;
        uint256 amount1 = freed1 + idleShare1;

        _burn(owner_, shares);

        if (amount0 > 0) IERC20(s.token0).safeTransfer(receiver, amount0);
        if (amount1 > 0) IERC20(s.token1).safeTransfer(receiver, amount1);

        assets =
            amount0 +
            VaultMath.token1ToToken0(
                amount1,
                OracleLib.getTwapSqrtPrice(s.pool, s.twapSeconds)
            );
        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    // ─── Token1 deposit ─────────────────────────────────────────────────────────

    /// @notice Preview shares for a token1 deposit (uses TWAP price).
    function previewDepositToken1(
        uint256 token1Amount
    ) public view returns (uint256) {
        if (token1Amount == 0) return 0;
        VaultStorageLib.VaultStorage storage s = _s();
        uint256 depositValToken0 = VaultMath.token1ToToken0(
            token1Amount,
            OracleLib.getTwapSqrtPrice(s.pool, s.twapSeconds)
        );
        if (depositValToken0 == 0) return 0;
        uint256 supply = totalSupply();
        uint256 ta = totalAssets();
        if (supply == 0)
            return
                depositValToken0 > DEAD_SHARES
                    ? depositValToken0 - DEAD_SHARES
                    : 0;
        if (ta == 0) return 0;
        return Math.mulDiv(depositValToken0, supply, ta, Math.Rounding.Floor);
    }

    /// @notice Deposit token1; shares priced via TWAP.
    function depositToken1(
        uint256 token1Amount,
        address receiver
    ) external whenNotPaused nonReentrant returns (uint256 shares) {
        if (token1Amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        _requireSpotNearTwap();

        VaultStorageLib.VaultStorage storage s = _s();
        s.lastDepositBlock[receiver] = block.number;

        uint256 totalValBefore = _totalVaultValueInToken0();
        uint256 supply = totalSupply();

        IERC20(s.token1).safeTransferFrom(
            msg.sender,
            address(this),
            token1Amount
        );

        uint256 depositValToken0 = VaultMath.token1ToToken0(
            token1Amount,
            OracleLib.getTwapSqrtPrice(s.pool, s.twapSeconds)
        );
        if (depositValToken0 == 0) revert ZeroAmount();

        if (supply == 0) {
            if (depositValToken0 <= DEAD_SHARES) revert BelowMinDeposit();
            _mint(address(0xdead), DEAD_SHARES);
            shares = depositValToken0 - DEAD_SHARES;
        } else {
            if (totalValBefore == 0) revert NoAssets();
            shares = Math.mulDiv(
                depositValToken0,
                supply,
                totalValBefore,
                Math.Rounding.Floor
            );
        }

        if (shares == 0) revert ZeroAmount();
        _mint(receiver, shares);
        emit Token1Deposited(msg.sender, receiver, token1Amount, shares);
    }

    // ─── Position lifecycle ──────────────────────────────────────────────────────

    /// @notice Deposit the vault's idle balances into a new CL position.
    function initializePosition(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external whenNotPaused onlyOwner nonReentrant {
        VaultStorageLib.VaultStorage storage s = _s();
        if (s.tokenId != 0) revert AlreadyInitialized();
        if (tickLower >= tickUpper) revert InvalidRange();

        // Adapter mint performs forceApprove(token0/1, positionManager) in vault context.
        (uint256 newTokenId, uint128 newLiquidity, , ) = _mintPosition(
            IDexAdapter.MintArgs({
                positionManager: s.positionManager,
                token0: s.token0,
                token1: s.token1,
                tickSpacing: _adapterTickSpacing(),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: address(this),
                deadline: block.timestamp + 300
            })
        );

        if (newLiquidity == 0) revert NoLiquidityMinted();
        s.tokenId = newTokenId;
        emit PositionInitialized(newTokenId, tickLower, tickUpper);
        emit Rebalanced(0, newTokenId, tickLower, tickUpper, newLiquidity);
    }

    /// @notice Collect accrued LP fees, deduct performance fee, and leave net in the vault.
    function collectFees(
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        whenNotPaused
        onlyOperator
        nonReentrant
        positionExists
        returns (uint256 net0, uint256 net1)
    {
        VaultStorageLib.VaultStorage storage s = _s();
        uint256 currentTokenId = s.tokenId;

        // Zero-liquidity decrease to flush feeGrowthInside into tokensOwed.
        _decreaseLiquidity(
            IDexAdapter.DecreaseArgs({
                positionManager: s.positionManager,
                tokenId: currentTokenId,
                liquidity: 0,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: block.timestamp + 300
            })
        );

        (, , uint128 tokensOwed0, uint128 tokensOwed1, , , ) = _adapterPositions(
            currentTokenId
        );

        _collect(
            IDexAdapter.CollectArgs({
                positionManager: s.positionManager,
                tokenId: currentTokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        (uint256 fee0, uint256 fee1) = _deductPerformanceFee(
            uint256(tokensOwed0),
            uint256(tokensOwed1)
        );
        net0 = uint256(tokensOwed0) - fee0;
        net1 = uint256(tokensOwed1) - fee1;

        s.totalFees0Earned += fee0;
        s.totalFees1Earned += fee1;
        if (fee0 > 0 || fee1 > 0)
            emit FeesCollected(fee0, fee1, s.feeRecipient);
    }

    /// @notice Remove all liquidity, collect fees, optionally swap for ratio, then re-mint
    ///         at a new TWAP-anchored range computed by the bound strategy module.
    /// @dev    The new range is anchored on the TWAP tick — not spot — to prevent a
    ///         flash-loan from forcing the vault into an attacker-chosen position.
    ///         All slippage floors (remove, swap, mint) are computed on-chain; the keeper
    ///         cannot pass zero min-amounts.
    function rebalance(
        bool swapZeroForOne,
        uint256 swapAmount
    ) external whenNotPaused onlyOperator nonReentrant positionExists {
        _requireSpotNearTwap();

        VaultStorageLib.VaultStorage storage s = _s();
        uint256 oldTokenId = s.tokenId;

        // Steps 1–4: remove liquidity, isolate + deduct fees, collect, burn.
        // Extracted to avoid stack-too-deep with the mint locals below.
        _rebalanceRemoveFeeCollectBurn(oldTokenId, s);

        // Step 5: optional ratio-alignment swap — TWAP-enforced slippage floor.
        if (swapAmount > 0) {
            _executeSwap(
                swapZeroForOne,
                swapAmount,
                VaultMath.computeSwapMinOut(
                    swapAmount,
                    swapZeroForOne,
                    OracleLib.getTwapSqrtPrice(s.pool, s.twapSeconds),
                    s.slippageBps
                )
            );
        }

        // Steps 6–7: compute new TWAP-anchored range and mint.
        _rebalanceMintNew(s, oldTokenId);
    }

    /// @dev Steps 1–4 of rebalance, extracted to reduce stack depth.
    ///      Snapshot owed before decrease, decrease, re-read owed, isolate fees,
    ///      deduct performance fee, collect, burn.
    function _rebalanceRemoveFeeCollectBurn(
        uint256 oldTokenId,
        VaultStorageLib.VaultStorage storage s
    ) private {
        (
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,
        ) = _adapterPositions(oldTokenId);

        // Snapshot owed BEFORE decrease.
        (, , uint128 owedBefore0, uint128 owedBefore1, , , ) = _adapterPositions(oldTokenId);

        uint256 principal0;
        uint256 principal1;
        if (liquidity > 0) {
            (uint256 rm0, uint256 rm1) = VaultMath.computeMintSlippage(
                OracleLib.getTwapSqrtPrice(s.pool, s.twapSeconds),
                tickLower, tickUpper, 0, 0, liquidity, s.slippageBps
            );
            (principal0, principal1) = _decreaseLiquidity(IDexAdapter.DecreaseArgs({
                positionManager: s.positionManager,
                tokenId: oldTokenId,
                liquidity: liquidity,
                amount0Min: rm0,
                amount1Min: rm1,
                deadline: block.timestamp + 300
            }));
        }

        // Re-read AFTER decrease: owed = owedBefore + newFees + principal.
        (, , uint128 tokensOwed0, uint128 tokensOwed1, , , ) = _adapterPositions(oldTokenId);

        // Fee isolation: (owedAfter − owedBefore) − principal = newly flushed fees.
        uint128 feesOwed0 = tokensOwed0 - owedBefore0 - uint128(principal0);
        uint128 feesOwed1 = tokensOwed1 - owedBefore1 - uint128(principal1);

        (uint256 fee0, uint256 fee1) = _deductPerformanceFee(uint256(feesOwed0), uint256(feesOwed1));
        s.totalFees0Earned += fee0;
        s.totalFees1Earned += fee1;
        if (fee0 > 0 || fee1 > 0) emit FeesCollected(fee0, fee1, s.feeRecipient);

        _collect(IDexAdapter.CollectArgs({
            positionManager: s.positionManager,
            tokenId: oldTokenId,
            recipient: address(this),
            amount0Max: tokensOwed0,
            amount1Max: tokensOwed1
        }));

        _burnPosition(oldTokenId);
    }

    /// @dev Steps 6–7 of rebalance: compute TWAP-anchored range, mint new position, commit.
    function _rebalanceMintNew(
        VaultStorageLib.VaultStorage storage s,
        uint256 oldTokenId
    ) private {
        int24 twapTick   = OracleLib.getTwapTick(s.pool, s.twapSeconds);
        int24 tickSpacing= _adapterTickSpacing();
        (int24 newLo, int24 newHi) = _strategyRange(twapTick, tickSpacing);

        uint256 bal0 = IERC20(s.token0).balanceOf(address(this));
        uint256 bal1 = IERC20(s.token1).balanceOf(address(this));
        if (bal0 == 0 && bal1 == 0) revert NothingToMint();

        (uint256 min0, uint256 min1) = VaultMath.computeMintSlippage(
            OracleLib.getTwapSqrtPrice(s.pool, s.twapSeconds),
            newLo, newHi, bal0, bal1, 0, s.slippageBps
        );

        (uint256 newTokenId, uint128 newLiquidity, , ) = _mintPosition(IDexAdapter.MintArgs({
            positionManager: s.positionManager,
            token0:          s.token0,
            token1:          s.token1,
            tickSpacing:     tickSpacing,
            tickLower:       newLo,
            tickUpper:       newHi,
            amount0Desired:  bal0,
            amount1Desired:  bal1,
            amount0Min:      min0,
            amount1Min:      min1,
            recipient:       address(this),
            deadline:        block.timestamp + 300
        }));

        if (newLiquidity == 0) revert NoLiquidityMinted();

        s.tokenId = newTokenId;
        s.rebalanceCount++;
        emit Rebalanced(oldTokenId, newTokenId, newLo, newHi, newLiquidity);
    }

    // ─── Admin ──────────────────────────────────────────────────────────────────

    function transferOwnership(address newOwner_) external onlyOwner {
        if (newOwner_ == address(0)) revert ZeroAddress();
        VaultStorageLib.VaultStorage storage s = _s();
        if (newOwner_ == s.owner) revert SameOwner();
        s.pendingOwner = newOwner_;
        emit OwnershipTransferStarted(s.owner, newOwner_);
    }

    function acceptOwnership() external {
        VaultStorageLib.VaultStorage storage s = _s();
        if (msg.sender != s.pendingOwner) revert NotPendingOwner();
        emit OwnershipTransferred(s.owner, s.pendingOwner);
        s.owner = s.pendingOwner;
        s.pendingOwner = address(0);
    }

    function setOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert ZeroAddress();
        _s().operator = newOperator;
        emit OperatorUpdated(newOperator);
    }

    function setPaused(bool _paused) external onlyOwner {
        _s().paused = _paused;
        emit VaultPaused(_paused);
    }

    /// @notice Pause callable by the guardian (e.g. via VaultFactory.pauseAll).
    function pauseByGuardian() external {
        if (msg.sender != _s().guardian) revert NotGuardian();
        _s().paused = true;
        emit VaultPaused(true);
    }

    function setGuardian(address newGuardian) external onlyOwner {
        if (newGuardian == address(0)) revert ZeroAddress();
        _s().guardian = newGuardian;
        emit GuardianUpdated(newGuardian);
    }

    function proposePerformanceFee(
        uint256 bps,
        address recipient
    ) external onlyOwner {
        if (bps > 1000) revert FeeTooHigh();
        if (recipient == address(0)) revert ZeroAddress();
        VaultStorageLib.VaultStorage storage s = _s();
        s.pendingFeeBps = bps;
        s.pendingFeeRecipient = recipient;
        s.feeChangeActiveAt = block.timestamp + 2 days;
        emit PerformanceFeeProposed(bps, recipient, s.feeChangeActiveAt);
    }

    function applyPerformanceFee() external onlyOwner {
        VaultStorageLib.VaultStorage storage s = _s();
        if (block.timestamp < s.feeChangeActiveAt) revert TimelockActive();
        s.performanceFeeBps = s.pendingFeeBps;
        s.feeRecipient = s.pendingFeeRecipient;
        emit PerformanceFeeUpdated(s.pendingFeeBps, s.pendingFeeRecipient);
    }

    /// @notice Begin a 2-day timelock to replace the strategy module.
    function proposeStrategy(address newStrategy) external onlyOwner {
        if (newStrategy == address(0)) revert ZeroAddress();
        VaultStorageLib.VaultStorage storage s = _s();
        s.pendingStrategy = newStrategy;
        s.strategyChangeActiveAt = block.timestamp + 2 days;
        emit StrategyProposed(newStrategy, s.strategyChangeActiveAt);
    }

    function applyStrategy() external onlyOwner {
        VaultStorageLib.VaultStorage storage s = _s();
        if (block.timestamp < s.strategyChangeActiveAt) revert TimelockActive();
        s.strategy = s.pendingStrategy;
        emit StrategyUpdated(s.pendingStrategy);
    }

    /// @notice Begin a 2-day timelock to replace the DEX adapter.
    /// @dev    The adapter runs via delegatecall — only adopt audited, stateless adapters.
    function proposeDexAdapter(address newAdapter) external onlyOwner {
        if (newAdapter == address(0)) revert ZeroAddress();
        VaultStorageLib.VaultStorage storage s = _s();
        s.pendingDexAdapter = newAdapter;
        s.dexAdapterChangeActiveAt = block.timestamp + 2 days;
        emit DexAdapterProposed(newAdapter, s.dexAdapterChangeActiveAt);
    }

    function applyDexAdapter() external onlyOwner {
        VaultStorageLib.VaultStorage storage s = _s();
        if (block.timestamp < s.dexAdapterChangeActiveAt)
            revert TimelockActive();
        s.dexAdapter = s.pendingDexAdapter;
        emit DexAdapterUpdated(s.pendingDexAdapter);
    }

    function sweepToken(address token, address to) external onlyOwner {
        VaultStorageLib.VaultStorage storage s = _s();
        if (token == s.token0 || token == s.token1) revert InvalidToken();
        if (to == address(0)) revert ZeroAddress();
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal == 0) revert ZeroAmount();
        IERC20(token).safeTransfer(to, bal);
        emit TokenSwept(token, to, bal);
    }

    function setTwapSeconds(uint32 seconds_) external onlyOwner {
        require(seconds_ >= 60, "Vault: twap too short");
        _s().twapSeconds = seconds_;
    }

    function setMaxTwapDeviationTicks(int24 ticks) external onlyOwner {
        require(ticks > 0 && ticks <= 1000, "Vault: deviation out of range");
        _s().maxTwapDeviationTicks = ticks;
    }

    function setSlippageBps(uint256 bps) external onlyOwner {
        require(bps <= 500, "Vault: slippage too high");
        _s().slippageBps = bps;
    }

    // ─── View helpers (absorbed from VaultLens) ──────────────────────────────────

    /// @notice Price of one share expressed in token0 units (scaled to token0 decimals).
    function sharePrice() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        return
            Math.mulDiv(
                totalAssets(),
                10 ** decimals(),
                supply,
                Math.Rounding.Floor
            );
    }

    /// @notice All key vault metrics in a single call.
    function getVaultMetrics()
        external
        view
        returns (
            uint256 tvl,
            int24 tickLower,
            int24 tickUpper,
            uint256 rebalCount,
            uint256 fees0Earned,
            uint256 fees1Earned
        )
    {
        VaultStorageLib.VaultStorage storage s = _s();
        tvl = totalAssets();
        rebalCount = s.rebalanceCount;
        fees0Earned = s.totalFees0Earned;
        fees1Earned = s.totalFees1Earned;
        if (s.tokenId != 0) {
            (tickLower, tickUpper, , , , , ) = _adapterPositions(s.tokenId);
        }
    }

    /// @notice Current pool price and tick from slot0.
    /// @dev WARNING: spot price — manipulable within a block. Do not use for pricing.
    function getPoolState()
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick)
    {
        return _adapterSlot0();
    }

    function getPosition()
        external
        view
        positionExists
        returns (
            address _token0,
            address _token1,
            int24 _tickSpacing,
            int24 _tickLower,
            int24 _tickUpper,
            uint128 _liquidity
        )
    {
        VaultStorageLib.VaultStorage storage s = _s();
        (
            _tickLower,
            _tickUpper,
            _liquidity,
            ,
            ,
            _token0,
            _token1
        ) = _adapterPositions(s.tokenId);
        _tickSpacing = _adapterTickSpacing();
    }

    function isOutOfRange() external view positionExists returns (bool) {
        (, int24 tick) = _adapterSlot0();
        (int24 lo, int24 hi, , , , , ) = _adapterPositions(_s().tokenId);
        return tick < lo || tick >= hi;
    }

    /// @notice Off-chain helper: optimal swap direction + amount before the next rebalance.
    function computeRebalanceParams()
        external
        view
        positionExists
        returns (bool swapZeroForOne, uint256 swapAmount)
    {
        VaultStorageLib.VaultStorage storage s = _s();
        (int24 lo, int24 hi, uint128 liq, , , , ) = _adapterPositions(s.tokenId);
        (uint160 sqrtPriceX96, ) = _adapterSlot0();

        (uint256 amount0, uint256 amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(lo),
                TickMath.getSqrtRatioAtTick(hi),
                liq
            );

        int24 twapTick = OracleLib.getTwapTick(s.pool, s.twapSeconds);
        int24 spacing = _adapterTickSpacing();
        (int24 rLo, int24 rHi) = IStrategy(s.strategy).computeRange(
            twapTick,
            spacing
        );

        return
            IStrategy(s.strategy).computeOptimalSwap(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(rLo),
                TickMath.getSqrtRatioAtTick(rHi),
                amount0,
                amount1
            );
    }

    // ─── ERC-721 receive / ETH ────────────────────────────────────────────────────

    receive() external payable {}

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // ─── Private: TWAP / price helpers ──────────────────────────────────────────

    function _requireSpotNearTwap() private view {
        VaultStorageLib.VaultStorage storage s = _s();
        OracleLib.requireSpotNearTwap(
            s.pool,
            s.twapSeconds,
            s.maxTwapDeviationTicks
        );
    }

    function _isDepositAllowed() private view returns (bool) {
        VaultStorageLib.VaultStorage storage s = _s();
        return
            OracleLib.isDepositAllowed(
                s.pool,
                s.twapSeconds,
                s.maxTwapDeviationTicks,
                s.paused
            );
    }

    // ─── Private: valuation ─────────────────────────────────────────────────────

    function _totalVaultValueInToken0() private view returns (uint256) {
        VaultStorageLib.VaultStorage storage s = _s();
        uint256 bal0 = IERC20(s.token0).balanceOf(address(this));
        uint256 bal1 = IERC20(s.token1).balanceOf(address(this));

        if (s.tokenId != 0) {
            uint160 sqrtTwap = OracleLib.getTwapSqrtPrice(
                s.pool,
                s.twapSeconds
            );
            (
                int24 lo,
                int24 hi,
                uint128 liq,
                uint128 owed0,
                uint128 owed1,
                ,
            ) = _adapterPositions(s.tokenId);
            (uint256 pos0, uint256 pos1) = LiquidityAmounts
                .getAmountsForLiquidity(
                    sqrtTwap,
                    TickMath.getSqrtRatioAtTick(lo),
                    TickMath.getSqrtRatioAtTick(hi),
                    liq
                );
            bal0 += pos0 + uint256(owed0);
            bal1 += pos1 + uint256(owed1);
        }

        if (bal1 == 0) return bal0;
        VaultStorageLib.VaultStorage storage s2 = _s();
        return
            bal0 +
            VaultMath.token1ToToken0(
                bal1,
                OracleLib.getTwapSqrtPrice(s2.pool, s2.twapSeconds)
            );
    }

    // ─── Private: slippage helpers ───────────────────────────────────────────────

    function _computeRemoveSlippage(
        uint256 shares,
        uint256 supply
    ) private view returns (uint256 min0, uint256 min1) {
        VaultStorageLib.VaultStorage storage s = _s();
        if (s.tokenId == 0) return (0, 0);
        (int24 lo, int24 hi, uint128 liq, , , , ) = _adapterPositions(s.tokenId);
        uint128 toRemove = uint128(
            Math.mulDiv(uint256(liq), shares, supply, Math.Rounding.Ceil)
        );
        if (toRemove == 0) return (0, 0);
        return
            VaultMath.computeMintSlippage(
                OracleLib.getTwapSqrtPrice(s.pool, s.twapSeconds),
                lo,
                hi,
                0,
                0,
                toRemove,
                s.slippageBps
            );
    }

    // ─── Private: liquidity removal ──────────────────────────────────────────────

    function _removeProportionalLiquidity(
        uint256 shares,
        uint256 supply,
        uint256 min0,
        uint256 min1
    ) private {
        VaultStorageLib.VaultStorage storage s = _s();
        if (s.tokenId == 0) return;
        (, , uint128 liq, , , , ) = _adapterPositions(s.tokenId);
        if (liq == 0) return;

        uint128 toRemove = uint128(
            Math.mulDiv(uint256(liq), shares, supply, Math.Rounding.Ceil)
        );
        if (toRemove == 0) return;

        _decreaseLiquidity(
            IDexAdapter.DecreaseArgs({
                positionManager: s.positionManager,
                tokenId: s.tokenId,
                liquidity: toRemove,
                amount0Min: min0,
                amount1Min: min1,
                deadline: block.timestamp + 300
            })
        );
        _collect(
            IDexAdapter.CollectArgs({
                positionManager: s.positionManager,
                tokenId: s.tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }

    // ─── Private: swap ───────────────────────────────────────────────────────────

    function _executeSwap(
        bool zeroForOne,
        uint256 amountIn,
        uint256 minOut
    ) private returns (uint256) {
        VaultStorageLib.VaultStorage storage s = _s();
        return
            _exactInputSingle(
                IDexAdapter.SwapArgs({
                    router: s.swapRouter,
                    tokenIn: zeroForOne ? s.token0 : s.token1,
                    tokenOut: zeroForOne ? s.token1 : s.token0,
                    tickSpacing: _adapterTickSpacing(),
                    recipient: address(this),
                    deadline: block.timestamp + 300,
                    amountIn: amountIn,
                    amountOutMinimum: minOut
                })
            );
    }

    // ─── Private: performance fee ────────────────────────────────────────────────

    function _deductPerformanceFee(
        uint256 earned0,
        uint256 earned1
    ) private returns (uint256 fee0, uint256 fee1) {
        VaultStorageLib.VaultStorage storage s = _s();
        if (s.performanceFeeBps == 0 || s.feeRecipient == address(0))
            return (0, 0);
        fee0 = Math.mulDiv(
            earned0,
            s.performanceFeeBps,
            10_000,
            Math.Rounding.Ceil
        );
        fee1 = Math.mulDiv(
            earned1,
            s.performanceFeeBps,
            10_000,
            Math.Rounding.Ceil
        );
        if (fee0 > 0) IERC20(s.token0).safeTransfer(s.feeRecipient, fee0);
        if (fee1 > 0) IERC20(s.token1).safeTransfer(s.feeRecipient, fee1);
    }

    // ─── Private: misc ───────────────────────────────────────────────────────────

    function _safeDecimals(address token) private view returns (uint8) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        if (ok && data.length >= 32) return abi.decode(data, (uint8));
        return 18;
    }

    // ─── Private: adapter read/write plumbing ────────────────────────────────────
    //
    // Reads go through normal external view calls (staticcall in EVM terms).
    // Writes are DELEGATECALLed into the stateless adapter so they execute in the
    // vault's context — tokens, the NFT, approvals, and refunds stay in the vault.

    function _adapterSlot0()
        private
        view
        returns (uint160 sqrtPriceX96, int24 tick)
    {
        VaultStorageLib.VaultStorage storage s = _s();
        return IDexAdapter(s.dexAdapter).slot0(s.pool);
    }

    function _adapterTickSpacing() private view returns (int24) {
        VaultStorageLib.VaultStorage storage s = _s();
        return IDexAdapter(s.dexAdapter).tickSpacing(s.pool);
    }

    function _adapterPositions(
        uint256 tokenId_
    )
        private
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint128 tokensOwed0,
            uint128 tokensOwed1,
            address t0,
            address t1
        )
    {
        VaultStorageLib.VaultStorage storage s = _s();
        return IDexAdapter(s.dexAdapter).positions(s.positionManager, tokenId_);
    }

    function _delegateAdapter(
        bytes memory data
    ) private returns (bytes memory) {
        (bool ok, bytes memory ret) = _s().dexAdapter.delegatecall(data);
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
        return ret;
    }

    /// @dev Named _mintPosition to avoid shadowing ERC20Upgradeable._mint.
    function _mintPosition(
        IDexAdapter.MintArgs memory a
    ) private returns (uint256 tokenId_, uint128 liq, uint256 a0, uint256 a1) {
        return
            abi.decode(
                _delegateAdapter(abi.encodeCall(IDexAdapter.mint, (a))),
                (uint256, uint128, uint256, uint256)
            );
    }

    function _decreaseLiquidity(
        IDexAdapter.DecreaseArgs memory a
    ) private returns (uint256 a0, uint256 a1) {
        return
            abi.decode(
                _delegateAdapter(
                    abi.encodeCall(IDexAdapter.decreaseLiquidity, (a))
                ),
                (uint256, uint256)
            );
    }

    function _collect(
        IDexAdapter.CollectArgs memory a
    ) private returns (uint256 a0, uint256 a1) {
        return
            abi.decode(
                _delegateAdapter(abi.encodeCall(IDexAdapter.collect, (a))),
                (uint256, uint256)
            );
    }

    /// @dev Named _burnPosition to avoid shadowing ERC20Upgradeable._burn.
    function _burnPosition(uint256 tokenId_) private {
        _delegateAdapter(
            abi.encodeCall(IDexAdapter.burn, (_s().positionManager, tokenId_))
        );
    }

    function _exactInputSingle(
        IDexAdapter.SwapArgs memory a
    ) private returns (uint256 amountOut) {
        return
            abi.decode(
                _delegateAdapter(
                    abi.encodeCall(IDexAdapter.exactInputSingle, (a))
                ),
                (uint256)
            );
    }

    /// @dev Staticcall the strategy then vault-validate: lo < hi, within TickMath bounds.
    function _strategyRange(
        int24 twapTick,
        int24 tickSpacing_
    ) private view returns (int24 lo, int24 hi) {
        (lo, hi) = IStrategy(_s().strategy).computeRange(
            twapTick,
            tickSpacing_
        );
        if (lo >= hi) revert InvalidRange();
        if (lo < TickMath.MIN_TICK || hi > TickMath.MAX_TICK)
            revert InvalidStrategyTicks();
    }
}
