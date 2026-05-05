// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// ─────────────────────────────────────────────────────────────────────────────
//  RebalancerVault — Automated LP Rebalancing Vault for Mezo DEX
//  Compatible with Mezo's CL (Uniswap V3 fork using tickSpacing instead of fee)
// ─────────────────────────────────────────────────────────────────────────────

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "./interfaces/INonFungiblePositionManager.sol";
import "./interfaces/ICLSwapRouter.sol";

contract RebalancerVault is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Mezo Mainnet Addresses ───────────────────────────────────────────────
    INonFungiblePositionManager public constant positionManager =
        INonFungiblePositionManager(0x509Bc221df2B83927c695FA0bb0f5B21053C874c);
    ICLSwapRouter public constant clSwapRouter =
        ICLSwapRouter(0x37cDd11919ec3860eaD9efB8673d7476E5326225);

    // ─── Vault Configuration ─────────────────────────────────────────────────
    address public owner;
    address public operator;
    bool public paused;

    /// @notice Performance fee in basis points (max 1000 = 10%). Charged on earned fees only.
    uint256 public performanceFeeBps;
    address public feeRecipient;

    // ─── Pool & Token State ───────────────────────────────────────────────────
    IUniswapV3Pool public immutable pool;
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    /// @dev Cached decimals for price-normalisation between token0 and token1
    uint8 public immutable decimals0;
    uint8 public immutable decimals1;

    /// @notice The NFT tokenId of the vault's active LP position (0 = uninitialised)
    uint256 public tokenId;

    // ─── Anti-inflation constants ─────────────────────────────────────────────
    /// @dev Permanently burned to dead address on first deposit to prevent share-price manipulation
    uint256 public constant DEAD_SHARES = 1_000;
    uint256 public constant MIN_INIT_VALUE = 1_001; // must exceed DEAD_SHARES

    // ─── Events ───────────────────────────────────────────────────────────────
    event Deposited(
        address indexed depositor,
        address indexed token,
        uint256 amount,
        uint256 shares
    );
    event Redeemed(
        address indexed redeemer,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
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

    // ─── Custom Errors ────────────────────────────────────────────────────────
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

    // ─── Modifiers ────────────────────────────────────────────────────────────
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Vault: paused");
        _;
    }

    modifier positionExists() {
        if (tokenId == 0) revert NotInitialized();
        _;
    }

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param _owner   Vault owner / admin address
    /// @param _pool    Address of the Mezo CL pool to manage liquidity in
    /// @param _operator Initial keeper / rebalancer address (should differ from _owner in prod)
    constructor(
        address _owner,
        address _pool,
        address _operator
    ) ERC20("Rebalancer Vault", "rVLT") {
        if (_owner == address(0)) revert ZeroAddress();
        if (_pool == address(0)) revert ZeroAddress();
        if (_operator == address(0)) revert ZeroAddress();

        owner = _owner;
        operator = _operator;
        pool = IUniswapV3Pool(_pool);

        address t0 = IUniswapV3Pool(_pool).token0();
        address t1 = IUniswapV3Pool(_pool).token1();
        token0 = IERC20(t0);
        token1 = IERC20(t1);

        // Cache decimals for price-normalisation
        decimals0 = _safeDecimals(t0);
        decimals1 = _safeDecimals(t1);

        // Approve CLSwapRouter to pull both tokens during swaps
        IERC20(t0).approve(address(clSwapRouter), type(uint256).max);
        IERC20(t1).approve(address(clSwapRouter), type(uint256).max);

        // Approve NonfungiblePositionManager to pull both tokens when minting positions
        IERC20(t0).approve(address(positionManager), type(uint256).max);
        IERC20(t1).approve(address(positionManager), type(uint256).max);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  ADMIN FUNCTIONS
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Transfer vault ownership
    function setOwner(address _owner) external onlyOwner {
        if (_owner == address(0)) revert ZeroAddress();
        owner = _owner;
    }

    /// @notice Update the keeper / operator address
    function setOperator(address _operator) external onlyOwner {
        if (_operator == address(0)) revert ZeroAddress();
        operator = _operator;
        emit OperatorUpdated(_operator);
    }

    /// @notice Pause or unpause vault (blocks deposits, redeems, rebalances)
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit VaultPaused(_paused);
    }

    /// @notice Set performance fee and its recipient
    /// @param bps       Fee in basis points (max 1000 = 10%)
    /// @param recipient Address that receives the fee
    function setPerformanceFee(
        uint256 bps,
        address recipient
    ) external onlyOwner {
        if (bps > 1000) revert FeeTooHigh();
        if (recipient == address(0)) revert ZeroAddress();
        performanceFeeBps = bps;
        feeRecipient = recipient;
        emit PerformanceFeeUpdated(bps, recipient);
    }

    /// @notice Rescue tokens that are NOT token0 or token1 (e.g. accidentally sent ERC-20s)
    function sweepToken(address token, address to) external onlyOwner {
        if (token == address(token0) || token == address(token1))
            revert InvalidToken();
        if (to == address(0)) revert ZeroAddress();
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal == 0) revert ZeroAmount();
        IERC20(token).safeTransfer(to, bal);
        emit TokenSwept(token, to, bal);
    }

    /// @notice Allows the vault to receive native BTC / ETH (e.g. for wBTC unwrap refunds)
    receive() external payable {}

    // ─────────────────────────────────────────────────────────────────────────
    //  POSITION INITIALISATION
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice One-time call to mint the vault's first LP position.
    ///         Owner must have deposited tokens into the vault before calling this.
    /// @param tickLower      Lower tick of the initial range
    /// @param tickUpper      Upper tick of the initial range
    /// @param amount0Desired Desired token0 to deploy
    /// @param amount1Desired Desired token1 to deploy
    /// @param amount0Min     Minimum token0 accepted (slippage protection)
    /// @param amount1Min     Minimum token1 accepted (slippage protection)
    function initializePosition(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external whenNotPaused onlyOwner nonReentrant {
        if (tokenId != 0) revert AlreadyInitialized();
        if (tickLower >= tickUpper) revert InvalidRange();

        (uint256 newTokenId, uint128 newLiquidity, , ) = positionManager.mint(
            INonFungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                tickSpacing: pool.tickSpacing(), // Mezo: tickSpacing replaces fee
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
        tokenId = newTokenId;

        emit PositionInitialized(newTokenId, tickLower, tickUpper);
        emit Rebalanced(0, newTokenId, tickLower, tickUpper, newLiquidity);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  DEPOSIT
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Deposit token0 or token1 into the vault and receive proportional vault shares.
    ///         Uses total vault value (idle balance + locked position) for fair share pricing.
    ///         First depositor receives shares minus DEAD_SHARES burned to prevent inflation attacks.
    /// @param token  Must be token0 or token1
    /// @param amount Amount to deposit (in token's native units)
    function deposit(
        address token,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (token != address(token0) && token != address(token1))
            revert InvalidToken();

        // ── Snapshot total vault value BEFORE transfer ────────────────────────
        uint256 totalValBefore = _totalVaultValueInToken0();

        // ── Pull tokens from depositor ────────────────────────────────────────
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // ── Express deposit in token0 units for share pricing ─────────────────
        uint256 depositValToken0 = (token == address(token0))
            ? amount
            : _token1ToToken0(amount);

        // ── Mint shares ───────────────────────────────────────────────────────
        uint256 supply = totalSupply();
        uint256 shares;

        if (supply == 0) {
            // First deposit: burn DEAD_SHARES to prevent share-price manipulation
            if (depositValToken0 <= DEAD_SHARES) revert BelowMinDeposit();
            _mint(address(0xdead), DEAD_SHARES);
            shares = depositValToken0 - DEAD_SHARES;
        } else {
            if (totalValBefore == 0) revert NoAssets();
            shares = FullMath.mulDiv(depositValToken0, supply, totalValBefore);
        }

        if (shares == 0) revert ZeroAmount();
        _mint(msg.sender, shares);

        emit Deposited(msg.sender, token, amount, shares);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  REDEEM
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Burn vault shares and receive proportional token0 + token1.
    ///         If there is an active position, proportional liquidity is withdrawn first.
    /// @param shares          Number of vault shares to burn
    /// @param amount0MinRedeem Minimum token0 to receive from position removal (slippage guard)
    /// @param amount1MinRedeem Minimum token1 to receive from position removal (slippage guard)
    function redeem(
        uint256 shares,
        uint256 amount0MinRedeem,
        uint256 amount1MinRedeem
    ) external whenNotPaused nonReentrant {
        if (shares == 0) revert ZeroAmount();
        uint256 supply = totalSupply();
        require(supply > 0, "Vault: empty supply");

        // ── Withdraw proportional liquidity from active position ───────────────
        if (tokenId != 0) {
            (, , , , , , , uint128 liquidity, , , , ) = positionManager
                .positions(tokenId);

            if (liquidity > 0) {
                // Calculate proportional liquidity to remove
                uint128 liquidityToRemove = uint128(
                    FullMath.mulDiv(uint256(liquidity), shares, supply)
                );

                if (liquidityToRemove > 0) {
                    positionManager.decreaseLiquidity(
                        INonFungiblePositionManager.DecreaseLiquidityParams({
                            tokenId: tokenId,
                            liquidity: liquidityToRemove,
                            amount0Min: amount0MinRedeem,
                            amount1Min: amount1MinRedeem,
                            deadline: block.timestamp + 300
                        })
                    );

                    positionManager.collect(
                        INonFungiblePositionManager.CollectParams({
                            tokenId: tokenId,
                            recipient: address(this),
                            amount0Max: type(uint128).max,
                            amount1Max: type(uint128).max
                        })
                    );
                }
            }
        }

        // ── Calculate proportional idle balances AFTER liquidity withdrawal ────
        uint256 bal0 = token0.balanceOf(address(this));
        uint256 bal1 = token1.balanceOf(address(this));

        uint256 amount0 = FullMath.mulDiv(bal0, shares, supply);
        uint256 amount1 = FullMath.mulDiv(bal1, shares, supply);

        // ── Burn shares AFTER amounts are calculated ──────────────────────────
        _burn(msg.sender, shares);

        // ── Transfer tokens to redeemer ───────────────────────────────────────
        if (amount0 > 0) token0.safeTransfer(msg.sender, amount0);
        if (amount1 > 0) token1.safeTransfer(msg.sender, amount1);

        emit Redeemed(msg.sender, shares, amount0, amount1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  FEE COLLECTION  (operator-callable, standalone)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Collect accrued trading fees from the active position without rebalancing.
    ///         Performance fee is deducted from earned fees and sent to feeRecipient.
    /// @param amount0Min Minimum token0 to receive (slippage guard)
    /// @param amount1Min Minimum token1 to receive (slippage guard)
    /// @return net0 Token0 retained by vault after fee deduction
    /// @return net1 Token1 retained by vault after fee deduction
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
        uint256 currentTokenId = tokenId;

        // Read tokens owed (earned fees) BEFORE decreaseLiquidity so we can
        // charge performanceFee only on fees, not on returned principal.
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = positionManager.positions(currentTokenId);

        // Trigger 0-liquidity decrease to flush tokensOwed into collect-able balance
        positionManager.decreaseLiquidity(
            INonFungiblePositionManager.DecreaseLiquidityParams({
                tokenId: currentTokenId,
                liquidity: 0,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: block.timestamp + 300
            })
        );

        positionManager.collect(
            INonFungiblePositionManager.CollectParams({
                tokenId: currentTokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // Charge performance fee only on earned fees (tokensOwed), not on liquidity principal
        (uint256 fee0, uint256 fee1) = _deductPerformanceFee(
            uint256(tokensOwed0),
            uint256(tokensOwed1)
        );

        net0 = uint256(tokensOwed0) - fee0;
        net1 = uint256(tokensOwed1) - fee1;

        if (fee0 > 0 || fee1 > 0) emit FeesCollected(fee0, fee1, feeRecipient);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  REBALANCE  (operator-callable)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Core rebalance: removes all liquidity, optionally swaps to rebalance ratio,
    ///         then mints a new position centred on the current tick.
    ///
    /// @param swapZeroForOne   True  → sell token0 for token1 before minting
    ///                         False → sell token1 for token0 before minting
    /// @param swapAmount       Amount of tokenIn to swap (0 = skip swap)
    /// @param swapAmountOutMin Minimum tokenOut from swap (slippage protection)
    /// @param amount0MinRemove Minimum token0 when removing liquidity
    /// @param amount1MinRemove Minimum token1 when removing liquidity
    /// @param amount0MinMint   Minimum token0 accepted when minting new position
    /// @param amount1MinMint   Minimum token1 accepted when minting new position
    function rebalance(
        bool swapZeroForOne,
        uint256 swapAmount,
        uint256 swapAmountOutMin,
        uint256 amount0MinRemove,
        uint256 amount1MinRemove,
        uint256 amount0MinMint,
        uint256 amount1MinMint
    ) external whenNotPaused onlyOperator nonReentrant positionExists {
        uint256 oldTokenId = tokenId;

        // ── Read old position ─────────────────────────────────────────────────
        (
            ,
            ,
            ,
            ,
            ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = positionManager.positions(oldTokenId);

        // ── Step 1: Remove all liquidity ──────────────────────────────────────
        if (liquidity > 0) {
            positionManager.decreaseLiquidity(
                INonFungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: oldTokenId,
                    liquidity: liquidity,
                    amount0Min: amount0MinRemove,
                    amount1Min: amount1MinRemove,
                    deadline: block.timestamp + 300
                })
            );
        }

        positionManager.collect(
            INonFungiblePositionManager.CollectParams({
                tokenId: oldTokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // ── Step 2: Deduct performance fee (on earned fees only, not principal) ─
        (uint256 fee0, uint256 fee1) = _deductPerformanceFee(
            uint256(tokensOwed0),
            uint256(tokensOwed1)
        );
        if (fee0 > 0 || fee1 > 0) emit FeesCollected(fee0, fee1, feeRecipient);

        // ── Step 3: Burn old NFT (single burn, after collect) ─────────────────
        positionManager.burn(oldTokenId);

        // ── Step 4: Optional swap to rebalance token ratio ────────────────────
        if (swapAmount > 0) {
            _executeSwap(swapZeroForOne, swapAmount, swapAmountOutMin);
        }

        // ── Step 5: Compute new centred tick range ────────────────────────────
        (, int24 currentTick, , , , , ) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        int24 halfWidth = (tickUpper - tickLower) / 2;

        int24 newTickLower = _floor(currentTick - halfWidth, tickSpacing);
        int24 newTickUpper = _ceil(currentTick + halfWidth, tickSpacing);

        // Validate before mint
        if (newTickLower >= newTickUpper) revert InvalidRange();

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        require(balance0 > 0 || balance1 > 0, "Vault: nothing to mint");

        // ── Step 6: Mint new position ─────────────────────────────────────────
        (uint256 newTokenId, uint128 newLiquidity, , ) = positionManager.mint(
            INonFungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                tickSpacing: tickSpacing,
                tickLower: newTickLower,
                tickUpper: newTickUpper,
                amount0Desired: balance0,
                amount1Desired: balance1,
                amount0Min: amount0MinMint,
                amount1Min: amount1MinMint,
                recipient: address(this),
                deadline: block.timestamp + 300
            })
        );

        if (newLiquidity == 0) revert NoLiquidityMinted();

        // ── Step 7: Commit new tokenId ────────────────────────────────────────
        tokenId = newTokenId;

        emit Rebalanced(
            oldTokenId,
            newTokenId,
            newTickLower,
            newTickUpper,
            newLiquidity
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  ERC-721 RECEIVER
    // ─────────────────────────────────────────────────────────────────────────

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  VIEW FUNCTIONS
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Current pool tick and sqrtPriceX96
    function getPoolState()
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick)
    {
        (sqrtPriceX96, tick, , , , , ) = pool.slot0();
    }

    /// @notice Active position details
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
        (
            ,
            ,
            _token0,
            _token1,
            ,
            _tickLower,
            _tickUpper,
            _liquidity,
            ,
            ,
            ,

        ) = positionManager.positions(tokenId);
        _tickSpacing = pool.tickSpacing();
    }

    /// @notice True if the current tick is outside the active position's range
    function isOutOfRange() external view positionExists returns (bool) {
        (, int24 tick, , , , , ) = pool.slot0();
        (, , , , , int24 lo, int24 hi, , , , , ) = positionManager.positions(
            tokenId
        );
        return tick < lo || tick >= hi;
    }

    /// @notice Total vault value expressed in token0 units
    ///         (idle wallet balance + value locked in active position, decimal-adjusted)
    function totalAssets() external view returns (uint256) {
        return _totalVaultValueInToken0();
    }

    /// @notice Price of one vault share in token0 units (18-decimal fixed point)
    function sharePrice() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        return FullMath.mulDiv(_totalVaultValueInToken0(), 1e18, supply);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  INTERNAL HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Floor-divide tick by spacing, correctly handling negative ticks
    function _floor(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 compressed = tick / spacing;
        if (tick < 0 && tick % spacing != 0) compressed--;
        return compressed * spacing;
    }

    /// @dev Ceiling-divide tick by spacing, correctly handling negative ticks
    function _ceil(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 floored = _floor(tick, spacing);
        return (floored == tick) ? tick : floored + spacing;
    }

    /// @dev Total vault value = idle token0 balance
    ///                        + idle token1 balance (converted to token0)
    ///                        + token0 locked in NFT position
    ///                        + token1 locked in NFT position (converted to token0)
    ///      All values are decimal-normalised.
    function _totalVaultValueInToken0() internal view returns (uint256) {
        uint256 bal0 = token0.balanceOf(address(this));
        uint256 bal1 = token1.balanceOf(address(this));

        if (tokenId != 0) {
            (uint256 pos0, uint256 pos1) = _getPositionAmounts();
            bal0 += pos0;
            bal1 += pos1;
        }

        return _valueInToken0(bal0, bal1);
    }

    /// @dev Converts a (bal0, bal1) pair to a single token0-denominated value.
    ///      Uses sqrtPriceX96 from pool.slot0() and normalises for decimal difference.
    function _valueInToken0(
        uint256 bal0,
        uint256 bal1
    ) internal view returns (uint256) {
        if (bal1 == 0) return bal0;

        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        // price = sqrtPriceX96² / 2¹⁹² (token1 per token0, in raw units)
        // value of bal1 in token0 raw units = bal1 * sqrtPriceX96² / 2¹⁹²
        uint256 temp = FullMath.mulDiv(
            bal1,
            uint256(sqrtPriceX96),
            uint256(1) << 96
        );
        uint256 val1InToken0 = FullMath.mulDiv(
            temp,
            uint256(sqrtPriceX96),
            uint256(1) << 96
        );

        // Normalise for decimal difference between token0 and token1
        if (decimals1 > decimals0) {
            val1InToken0 =
                val1InToken0 /
                (10 ** uint256(decimals1 - decimals0));
        } else if (decimals0 > decimals1) {
            val1InToken0 =
                val1InToken0 *
                (10 ** uint256(decimals0 - decimals1));
        }

        return bal0 + val1InToken0;
    }

    /// @dev Converts a token1 amount to token0 units using pool spot price + decimal adjustment
    function _token1ToToken0(uint256 amount1) internal view returns (uint256) {
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint256 temp = FullMath.mulDiv(
            amount1,
            uint256(sqrtPriceX96),
            uint256(1) << 96
        );
        uint256 result = FullMath.mulDiv(
            temp,
            uint256(sqrtPriceX96),
            uint256(1) << 96
        );
        if (decimals1 > decimals0) {
            result = result / (10 ** uint256(decimals1 - decimals0));
        } else if (decimals0 > decimals1) {
            result = result * (10 ** uint256(decimals0 - decimals1));
        }
        return result;
    }

    /// @dev Returns (amount0, amount1) currently locked in the vault's NFT position.
    ///      Uses LiquidityAmounts library with current pool sqrtPrice.
    function _getPositionAmounts()
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        if (tokenId == 0) return (0, 0);

        (
            ,
            ,
            ,
            ,
            ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = positionManager.positions(tokenId);

        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );
    }

    /// @dev Execute a single-hop exactInputSingle swap via the Mezo CLSwapRouter.
    ///      Uses tickSpacing (not fee) per Mezo's CL router interface.
    function _executeSwap(
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal returns (uint256 amountOut) {
        address tokenIn = zeroForOne ? address(token0) : address(token1);
        address tokenOut = zeroForOne ? address(token1) : address(token0);

        amountOut = clSwapRouter.exactInputSingle(
            ICLSwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                tickSpacing: pool.tickSpacing(),
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /// @dev Deducts performance fee from earned fee amounts and transfers to feeRecipient.
    ///      Returns (fee0, fee1) deducted. Pass tokensOwed values — NOT full collected amounts.
    function _deductPerformanceFee(
        uint256 earned0,
        uint256 earned1
    ) internal returns (uint256 fee0, uint256 fee1) {
        if (performanceFeeBps == 0 || feeRecipient == address(0)) return (0, 0);

        fee0 = FullMath.mulDiv(earned0, performanceFeeBps, 10_000);
        fee1 = FullMath.mulDiv(earned1, performanceFeeBps, 10_000);

        if (fee0 > 0) token0.safeTransfer(feeRecipient, fee0);
        if (fee1 > 0) token1.safeTransfer(feeRecipient, fee1);
    }

    /// @dev Safely read decimals from a token, defaulting to 18 if the call fails
    function _safeDecimals(address token) internal view returns (uint8) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        if (ok && data.length >= 32) return abi.decode(data, (uint8));
        return 18;
    }
}
