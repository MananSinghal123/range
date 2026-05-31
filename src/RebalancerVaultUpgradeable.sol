// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICLPool} from "./interfaces/ICLPool.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {ICLSwapRouter} from "./interfaces/ICLSwapRouter.sol";
import {IDexAdapter} from "./interfaces/IDexAdapter.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {VaultStorageLib} from "./libraries/VaultStorageLib.sol";

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

contract RebalancerVaultUpgradeable is
    Initializable,
    ERC20Upgradeable,
    ERC4626Upgradeable,
    ReentrancyGuardTransient
{
    using SafeERC20 for IERC20;

    uint256 public constant DEAD_SHARES = 1_000;

    // ─── Events (parity with RebalancerVault.sol) ───────────────────────────────
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

    // ─── Events (new: modular module timelocks + guardian) ──────────────────────
    event StrategyProposed(address strategy);
    event StrategyUpdated(address strategy);
    event DexAdapterProposed(address dexAdapter);
    event DexAdapterUpdated(address dexAdapter);
    event GuardianUpdated(address guardian);

    // ─── Errors (parity with RebalancerVault.sol) ───────────────────────────────
    error NotOwner();
    error NotOperator();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidToken();
    error AlreadyInitialized();
    error NotInitialized();
    error InvalidRange();
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

    // ─── Errors (new: modular) ──────────────────────────────────────────────────
    error NotGuardian();
    error InvalidStrategyTicks();

    /// @notice Parameters consumed once by {initialize}. Field order is part of the ABI
    ///         the factory encodes against — do not reorder.
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

    // ─── Modifiers (read from namespaced storage) ───────────────────────────────
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

    constructor() {
        _disableInitializers();
    }

    /// @dev Namespaced storage accessor.
    function _s() private pure returns (VaultStorageLib.VaultStorage storage) {
        return VaultStorageLib.get();
    }

    /// @notice One-time initializer (replaces the monolith constructor).
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

        VaultStorageLib.VaultStorage storage s = _s();

        // access control / lifecycle
        s.owner = p.owner;
        s.operator = p.operator;
        s.guardian = p.guardian;

        // swappable modules
        s.strategy = p.strategy;
        s.dexAdapter = p.dexAdapter;

        // DEX wiring
        s.pool = p.pool;
        s.positionManager = p.positionManager;
        s.swapRouter = p.swapRouter;

        address t0 = ICLPool(p.pool).token0();
        address t1 = ICLPool(p.pool).token1();
        s.token0 = t0;
        s.token1 = t1;
        s.decimals0 = _safeDecimals(t0);
        s.decimals1 = _safeDecimals(t1);

        // fees
        s.performanceFeeBps = 1000;
        s.feeRecipient = p.feeRecipient;

        // oracle / guard params
        s.twapSeconds = 300;
        s.maxTwapDeviationTicks = 200;
        s.slippageBps = 50;
    }

    /// @dev Safely read decimals() from a token; defaults to 18 if the call fails.
    function _safeDecimals(address token) internal view returns (uint8) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        if (ok && data.length >= 32) return abi.decode(data, (uint8));
        return 18;
    }

    // ─── ERC4626 view wiring ────────────────────────────────────────────────────

    /// @notice Vault decimals follow token0's decimals (parity with the monolith).
    function decimals()
        public
        view
        override(ERC20Upgradeable, ERC4626Upgradeable)
        returns (uint8)
    {
        return _s().decimals0;
    }

    /// @notice The underlying asset is token0. (ERC4626 already stores this via
    ///         __ERC4626_init; we override to read the canonical namespaced value.)
    function asset() public view override returns (address) {
        return _s().token0;
    }

    // ─── Public getters (namespaced storage) ────────────────────────────────────

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

    function positionManager() public view returns (INonfungiblePositionManager) {
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

    // ─── Lifecycle (STUBS — bodies implemented in later tasks) ───────────────────

    /// @notice Initialize the single CL position the vault manages.
    /// @dev STUB: implemented in Task 11. Symbol exists so IRebalancerVault and the
    ///      shared test base compile.
    function initializePosition(
        int24, /* tickLower */
        int24, /* tickUpper */
        uint256, /* amount0Desired */
        uint256, /* amount1Desired */
        uint256, /* amount0Min */
        uint256 /* amount1Min */
    ) external {
        revert("unimplemented");
    }

    // ─── Adapter / strategy plumbing ────────────────────────────────────────────
    //
    // Reads are normal external view calls (STATICCALL) to the adapter address.
    // Writes are DELEGATECALLed into the (stateless) adapter so they execute in the
    // vault's context — the vault keeps custody of tokens, the NFT, approvals, and
    // refunds. The strategy is only ever STATICCALLed; the vault re-validates the
    // ticks it returns before using them.

    /// @dev STATICCALL: current pool price/tick via the adapter.
    function _adapterSlot0() private view returns (uint160 sqrtPriceX96, int24 tick) {
        return IDexAdapter(_s().dexAdapter).slot0(_s().pool);
    }

    /// @dev STATICCALL: pool tick spacing via the adapter.
    function _adapterTickSpacing() private view returns (int24) {
        return IDexAdapter(_s().dexAdapter).tickSpacing(_s().pool);
    }

    /// @dev STATICCALL: position data for `tokenId_` via the adapter.
    function _adapterPositions(uint256 tokenId_)
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
        return IDexAdapter(_s().dexAdapter).positions(_s().positionManager, tokenId_);
    }

    /// @dev DELEGATECALL into the adapter, bubbling up any revert reason verbatim.
    function _delegateAdapter(bytes memory data) private returns (bytes memory) {
        (bool ok, bytes memory ret) = _s().dexAdapter.delegatecall(data);
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
        return ret;
    }

    /// @dev DELEGATECALL: mint a new position. Named `_mintPosition` to avoid
    ///      colliding with ERC20Upgradeable's internal `_mint`.
    function _mintPosition(IDexAdapter.MintArgs memory a)
        private
        returns (uint256 tokenId_, uint128 liq, uint256 a0, uint256 a1)
    {
        bytes memory ret = _delegateAdapter(abi.encodeCall(IDexAdapter.mint, (a)));
        return abi.decode(ret, (uint256, uint128, uint256, uint256));
    }

    /// @dev DELEGATECALL: decrease liquidity on an existing position.
    function _decreaseLiquidity(IDexAdapter.DecreaseArgs memory a)
        private
        returns (uint256 a0, uint256 a1)
    {
        bytes memory ret = _delegateAdapter(abi.encodeCall(IDexAdapter.decreaseLiquidity, (a)));
        return abi.decode(ret, (uint256, uint256));
    }

    /// @dev DELEGATECALL: collect owed tokens/fees from a position.
    function _collect(IDexAdapter.CollectArgs memory a)
        private
        returns (uint256 a0, uint256 a1)
    {
        bytes memory ret = _delegateAdapter(abi.encodeCall(IDexAdapter.collect, (a)));
        return abi.decode(ret, (uint256, uint256));
    }

    /// @dev DELEGATECALL: burn the position NFT. Named `_burnPosition` to avoid
    ///      colliding with ERC20Upgradeable's internal `_burn`.
    function _burnPosition(uint256 tokenId_) private {
        _delegateAdapter(abi.encodeCall(IDexAdapter.burn, (_s().positionManager, tokenId_)));
    }

    /// @dev DELEGATECALL: single-hop exact-input swap via the router.
    function _exactInputSingle(IDexAdapter.SwapArgs memory a) private returns (uint256 amountOut) {
        bytes memory ret = _delegateAdapter(abi.encodeCall(IDexAdapter.exactInputSingle, (a)));
        return abi.decode(ret, (uint256));
    }

    /// @dev STATICCALL the strategy for a range, then validate it vault-side:
    ///      lo < hi and both within global tick bounds.
    function _strategyRange(int24 twapTick, int24 tickSpacing_)
        private
        view
        returns (int24 lo, int24 hi)
    {
        (lo, hi) = IStrategy(_s().strategy).computeRange(twapTick, tickSpacing_);
        if (lo >= hi) revert InvalidRange();
        if (lo < TickMath.MIN_TICK || hi > TickMath.MAX_TICK) revert InvalidStrategyTicks();
    }

    /// @notice Returns current pool price and tick from slot0.
    /// @dev WARNING: slot0 is the instantaneous price and can be manipulated within a single
    ///      block via flash loans. Do NOT use for pricing decisions. Use the TWAP for value-sensitive ops.
    function getPoolState() external view returns (uint160 sqrtPriceX96, int24 tick) {
        return _adapterSlot0();
    }

    // ─── ERC721 / ETH receive (parity with RebalancerVault.sol) ─────────────────

    receive() external payable {}

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
