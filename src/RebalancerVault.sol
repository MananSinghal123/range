// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/INonfungiblePositionManager.sol";
import "./interfaces/ICLSwapRouter.sol";
import "./interfaces/ICLPool.sol";

contract RebalancerVault is ReentrancyGuard, ERC4626 {
    using SafeERC20 for IERC20;

    INonfungiblePositionManager public constant positionManager =
        INonfungiblePositionManager(0x509Bc221df2B83927c695FA0bb0f5B21053C874c);
    ICLSwapRouter public constant clSwapRouter =
        ICLSwapRouter(0x37cDd11919ec3860eaD9efB8673d7476E5326225);

    address public owner;
    address public pendingOwner;
    address public operator;
    bool public paused;
    mapping(address => uint256) lastDepositBlock;
    uint256 public performanceFeeBps;
    address public feeRecipient;

    /// @notice Pending performance fee configuration waiting for timelock
    uint256 public pendingFeeBps;
    address public pendingFeeRecipient;
    /// @notice Timestamp when pending fee change becomes active
    uint256 public feeChangeActiveAt;

    uint32 public twapSeconds = 300;

    int24 public maxTwapDeviationTicks = 200;

    uint256 public slippageBps = 50;

    ICLPool public immutable pool;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint8 public immutable decimals0;
    uint8 public immutable decimals1;

    uint256 public tokenId;

    uint256 public rebalanceCount;
    uint256 public totalFees0Earned;
    uint256 public totalFees1Earned;

    uint256 public constant DEAD_SHARES = 1_000;

    enum StrategyType {
        TIGHT,
        MEDIUM,
        WIDE
    }
    StrategyType public strategyType;
    mapping(StrategyType => int24) public strategyWidths;

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
    event StrategyWidthSet(StrategyType indexed strategy, int24 width);

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

    constructor(
        address _owner,
        address _pool,
        address _operator,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) ERC4626(IERC20(ICLPool(_pool).token0())) {
        if (_owner == address(0)) revert ZeroAddress();
        if (_pool == address(0)) revert ZeroAddress();
        if (_operator == address(0)) revert ZeroAddress();

        owner = _owner;
        operator = _operator;
        pool = ICLPool(_pool);

        address t0 = ICLPool(_pool).token0();
        address t1 = ICLPool(_pool).token1();
        token0 = IERC20(t0);
        token1 = IERC20(t1);

        decimals0 = _safeDecimals(t0);
        decimals1 = _safeDecimals(t1);

        strategyWidths[StrategyType.TIGHT] = 300;
        strategyWidths[StrategyType.MEDIUM] = 700;
        strategyWidths[StrategyType.WIDE] = 1200;

        performanceFeeBps = 1000;
        feeRecipient = _owner;
    }

    function decimals() public view override(ERC4626) returns (uint8) {
        return decimals0;
    }

    function asset() public view override returns (address assetTokenAddress) {
        return address(token0);
    }

    function totalAssets() public view override(ERC4626) returns (uint256) {
        return _totalVaultValueInToken0();
    }

    function convertToShares(
        uint256 assets
    ) public view override returns (uint256 shares) {
        uint256 supply = totalSupply();
        uint256 ta = totalAssets();
        if (supply == 0) return assets;
        if (ta == 0) return 0;
        return Math.mulDiv(assets, supply, ta, Math.Rounding.Floor);
    }

    function convertToAssets(
        uint256 shares
    ) public view override returns (uint256 assets) {
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

    /// @inheritdoc IERC4626
    function maxDeposit(
        address
    ) public view override(ERC4626) returns (uint256) {
        return _isDepositAllowed() ? type(uint256).max : 0;
    }

    function previewDeposit(
        uint256 assets
    ) public view override(ERC4626) returns (uint256) {
        uint256 supply = totalSupply();
        uint256 ta = totalAssets();

        if (supply == 0) {
            return assets > DEAD_SHARES ? assets - DEAD_SHARES : 0;
        }

        if (ta == 0) return 0;

        return Math.mulDiv(assets, supply, ta, Math.Rounding.Floor);
    }

    function deposit(
        uint256 assets,
        address receiver
    )
        public
        override(ERC4626)
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (assets > maxDeposit(receiver)) revert ExceedsMaxDeposit();
        _requireSpotNearTwap();
        lastDepositBlock[receiver] = block.number;

        uint256 totalValBefore = _totalVaultValueInToken0();
        uint256 supply = totalSupply();

        token0.safeTransferFrom(msg.sender, address(this), assets);

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

    /// @notice Preview shares minted for a given token1 deposit amount.
    /// @dev Mirrors previewDeposit but converts token1 to token0 first via
    ///      the pool's current spot price. Subject to the same spot-price
    ///      manipulation risk as depositToken1 itself — do not use for
    ///      value-sensitive off-chain decisions.
    /// @param token1Amount Amount of token1 to deposit
    /// @return shares Shares that would be minted (0 if deposit would fail)
    function previewDepositToken1(
        uint256 token1Amount
    ) public view returns (uint256) {
        if (token1Amount == 0) return 0;

        uint256 depositValToken0 = _token1ToToken0(token1Amount);
        if (depositValToken0 == 0) return 0;

        uint256 supply = totalSupply();
        uint256 ta = totalAssets();

        if (supply == 0) {
            return
                depositValToken0 > DEAD_SHARES
                    ? depositValToken0 - DEAD_SHARES
                    : 0;
        }

        if (ta == 0) return 0;

        return Math.mulDiv(depositValToken0, supply, ta, Math.Rounding.Floor);
    }

    function depositToken1(
        uint256 token1Amount,
        address receiver
    ) external whenNotPaused nonReentrant returns (uint256 shares) {
        if (token1Amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        // Guard: share issuance priced via TWAP; reject when spot deviates.
        _requireSpotNearTwap();
        lastDepositBlock[receiver] = block.number;

        uint256 totalValBefore = _totalVaultValueInToken0();
        uint256 supply = totalSupply();

        token1.safeTransferFrom(msg.sender, address(this), token1Amount);

        uint256 depositValToken0 = _token1ToToken0(token1Amount);
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

    /// @inheritdoc IERC4626
    function maxMint(address) public view override(ERC4626) returns (uint256) {
        return _isDepositAllowed() ? type(uint256).max : 0;
    }

    function previewMint(
        uint256 shares
    ) public view override(ERC4626) returns (uint256) {
        uint256 supply = totalSupply();

        if (supply == 0) return shares + DEAD_SHARES;

        uint256 ta = totalAssets();
        if (ta == 0) return type(uint256).max;
        if (shares == 0) return 0;

        return Math.mulDiv(shares, ta, supply, Math.Rounding.Ceil);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public override whenNotPaused nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (shares > maxMint(receiver)) revert ExceedsMaxMint();
        _requireSpotNearTwap();
        lastDepositBlock[receiver] = block.number;

        uint256 supply = totalSupply();
        uint256 ta = totalAssets();

        if (supply > 0 && ta == 0) revert NoAssets();

        assets = previewMint(shares);

        if (assets == 0 || assets == type(uint256).max) revert ZeroAmount();

        token0.safeTransferFrom(msg.sender, address(this), assets);

        if (supply == 0) {
            _mint(address(0xdead), DEAD_SHARES);
        }

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(
        address owner_
    ) public view override(ERC4626) returns (uint256) {
        if (paused) return 0;
        return convertToAssets(balanceOf(owner_));
    }

    function previewWithdraw(
        uint256 assets
    ) public view override(ERC4626) returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return type(uint256).max;

        uint256 ta = totalAssets();
        if (ta == 0) return type(uint256).max;
        if (assets == 0) return 0;

        return Math.mulDiv(assets, supply, ta, Math.Rounding.Ceil);
    }

    /// @inheritdoc IERC4626
    /// @dev Slippage floors computed on-chain from TWAP + slippageBps.
    ///      Use withdrawWithSlippage() for caller-supplied min amounts.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner_
    )
        public
        override(ERC4626)
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        require(block.number > lastDepositBlock[owner_], "same block");
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (assets > maxWithdraw(owner_)) revert ExceedsMaxWithdraw();

        _requireSpotNearTwap();

        shares = previewWithdraw(assets);
        if (shares == 0 || shares == type(uint256).max) revert ZeroAmount();

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, shares);
        }

        uint256 supply = totalSupply();
        (uint256 min0, uint256 min1) = _computeRemoveSlippage(shares, supply);
        _removeProportionalLiquidity(shares, supply, min0, min1);
        _burn(owner_, shares);

        uint256 idle0 = token0.balanceOf(address(this));
        if (idle0 < assets) {
            uint256 shortfall = assets - idle0;
            uint256 token1Needed = _token0ToToken1(shortfall);
            uint256 available1 = token1.balanceOf(address(this));
            if (token1Needed > available1) token1Needed = available1;
            if (token1Needed > 0) {
                uint256 swapMin = _computeSwapMinOut(token1Needed, false);
                _ensureAllowance(token1, address(clSwapRouter), token1Needed);
                _executeSwap(false, token1Needed, swapMin);
            }
        }

        uint256 finalIdle0 = token0.balanceOf(address(this));
        if (finalIdle0 < assets)
            revert InsufficientToken0ForWithdraw(finalIdle0, assets);

        token0.safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    /// @inheritdoc IERC4626
    function maxRedeem(
        address owner_
    ) public view override(ERC4626) returns (uint256) {
        return paused ? 0 : balanceOf(owner_);
    }

    /// @inheritdoc IERC4626
    /// @dev Rounds DOWN per spec (mulDiv floors) — caller gets no more than their fair share.
    function previewRedeem(
        uint256 shares
    ) public view override(ERC4626) returns (uint256) {
        return convertToAssets(shares);
    }

    /// @inheritdoc IERC4626
    function redeem(
        uint256 shares,
        address receiver,
        address owner_
    ) public override whenNotPaused nonReentrant returns (uint256 assets) {
        require(block.number > lastDepositBlock[owner_], "same block");
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (shares > maxRedeem(owner_)) revert ExceedsMaxRedeem();

        _requireSpotNearTwap();

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, shares);
        }

        uint256 supply = totalSupply();

        uint256 idleBefore0 = token0.balanceOf(address(this));
        uint256 idleBefore1 = token1.balanceOf(address(this));

        (uint256 min0, uint256 min1) = _computeRemoveSlippage(shares, supply);

        _removeProportionalLiquidity(shares, supply, min0, min1);

        uint256 freed0 = token0.balanceOf(address(this)) - idleBefore0;
        uint256 freed1 = token1.balanceOf(address(this)) - idleBefore1;

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

        if (amount0 > 0) token0.safeTransfer(receiver, amount0);
        if (amount1 > 0) token1.safeTransfer(receiver, amount1);

        assets = amount0 + _token1ToToken0(amount1);

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert ZeroAddress();
        if (_newOwner == owner) revert SameOwner();
        pendingOwner = _newOwner;
        emit OwnershipTransferStarted(owner, _newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    function setOperator(address _operator) external onlyOwner {
        if (_operator == address(0)) revert ZeroAddress();
        operator = _operator;
        emit OperatorUpdated(_operator);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit VaultPaused(_paused);
    }

    function proposePerformanceFee(
        uint256 bps,
        address recipient
    ) external onlyOwner {
        if (bps > 1000) revert FeeTooHigh();
        if (recipient == address(0)) revert ZeroAddress();
        pendingFeeBps = bps;
        pendingFeeRecipient = recipient;
        feeChangeActiveAt = block.timestamp + 2 days;
        emit PerformanceFeeProposed(bps, recipient, feeChangeActiveAt);
    }

    //audited
    function applyPerformanceFee() external onlyOwner {
        if (block.timestamp < feeChangeActiveAt) revert TimelockActive();
        performanceFeeBps = pendingFeeBps;
        feeRecipient = pendingFeeRecipient;
        emit PerformanceFeeUpdated(pendingFeeBps, pendingFeeRecipient);
    }

    function sweepToken(address token, address to) external onlyOwner {
        if (token == address(token0) || token == address(token1))
            revert InvalidToken();
        if (to == address(0)) revert ZeroAddress();
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal == 0) revert ZeroAmount();
        IERC20(token).safeTransfer(to, bal);
        emit TokenSwept(token, to, bal);
    }

    receive() external payable {}

    /// @notice Override the half-width (in ticks) for a specific strategy.
    function setStrategyWidth(
        StrategyType strategy,
        int24 width
    ) external onlyOwner {
        require(width > 0, "Vault: width must be positive");
        strategyWidths[strategy] = width;
        emit StrategyWidthSet(strategy, width);
    }

    /// @notice Set the TWAP observation window. Minimum 60 s; recommend ≥300 s on mainnet.
    function setTwapSeconds(uint32 seconds_) external onlyOwner {
        require(seconds_ >= 60, "Vault: twap too short");
        twapSeconds = seconds_;
    }

    /// @notice Set the maximum |spotTick − twapTick| tolerated on write-paths. Max 1000.
    function setMaxTwapDeviationTicks(int24 ticks) external onlyOwner {
        require(ticks > 0 && ticks <= 1000, "Vault: deviation out of range");
        maxTwapDeviationTicks = ticks;
    }

    /// @notice Set the on-chain slippage tolerance in bps. Max 500 (5%).
    function setSlippageBps(uint256 bps) external onlyOwner {
        require(bps <= 500, "Vault: slippage too high");
        slippageBps = bps;
    }

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

        _ensureAllowance(token0, address(positionManager), amount0Desired);
        _ensureAllowance(token1, address(positionManager), amount1Desired);

        (uint256 newTokenId, uint128 newLiquidity, , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                tickSpacing: pool.tickSpacing(),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: address(this),
                deadline: block.timestamp + 300,
                sqrtPriceX96: 0
            })
        );

        if (newLiquidity == 0) revert NoLiquidityMinted();
        tokenId = newTokenId;

        emit PositionInitialized(newTokenId, tickLower, tickUpper);
        emit Rebalanced(0, newTokenId, tickLower, tickUpper, newLiquidity);
    }

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

        positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: currentTokenId,
                liquidity: 0,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: block.timestamp + 300
            })
        );

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

        positionManager.collect(
            INonfungiblePositionManager.CollectParams({
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

        totalFees0Earned += fee0;
        totalFees1Earned += fee1;
        if (fee0 > 0 || fee1 > 0) emit FeesCollected(fee0, fee1, feeRecipient);
    }

    /// @dev All slippage floors (remove, swap, mint) are computed on-chain from TWAP +
    ///      slippageBps — keepers cannot pass zero min-amounts.
    ///      The new range is anchored on the TWAP tick, not spot, to prevent a flash-loan
    ///      from locking the vault into an attacker-chosen position.
    function rebalance(
        bool swapZeroForOne,
        uint256 swapAmount,
        StrategyType strategy
    ) external whenNotPaused onlyOperator nonReentrant positionExists {
        // Refuse to rebalance when spot has drifted from TWAP — prevents an attacker
        // from sandwiching the ratio-swap that follows.
        _requireSpotNearTwap();

        uint256 oldTokenId = tokenId;

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

        uint256 principal0;
        uint256 principal1;

        // Step 1: Remove all liquidity — slippage floor computed on-chain, not caller-supplied.
        if (liquidity > 0) {
            (uint256 rm0, uint256 rm1) = _computeMintSlippage(
                tickLower,
                tickUpper,
                0,
                0,
                liquidity
            );
            (principal0, principal1) = positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: oldTokenId,
                    liquidity: liquidity,
                    amount0Min: rm0,
                    amount1Min: rm1,
                    deadline: block.timestamp + 300
                })
            );
        }

        (, , , , , , , , , , tokensOwed0, tokensOwed1) = positionManager
            .positions(oldTokenId);

        // tokensOwed now = all fees (including fresh feeGrowthInside flush) + principal     // subtract principal to isolate earned fees only:
        uint128 feesOwed0 = tokensOwed0 - uint128(principal0);
        uint128 feesOwed1 = tokensOwed1 - uint128(principal1);

        (uint256 fee0, uint256 fee1) = _deductPerformanceFee(
            uint256(feesOwed0),
            uint256(feesOwed1)
        );
        totalFees0Earned += fee0;
        totalFees1Earned += fee1;
        if (fee0 > 0 || fee1 > 0) emit FeesCollected(fee0, fee1, feeRecipient);

        positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: oldTokenId,
                recipient: address(this),
                amount0Max: tokensOwed0,
                amount1Max: tokensOwed1
            })
        );

        // Step 3: Burn old NFT
        positionManager.burn(oldTokenId);

        // Step 4: Optional ratio-alignment swap — TWAP-enforced slippage floor.
        if (swapAmount > 0) {
            uint256 swapMin = _computeSwapMinOut(swapAmount, swapZeroForOne);
            _executeSwap(swapZeroForOne, swapAmount, swapMin);
        }

        // Step 5: Compute new range centred on TWAP tick (not spot) to prevent a
        //         flash-loan from anchoring the vault at an attacker-chosen price.
        int24 twapTick = _getTwapTick();
        int24 tickSpacing = pool.tickSpacing();
        int24 halfWidth = strategyWidths[strategy];

        int24 newTickLower = _floor(twapTick - halfWidth, tickSpacing);
        int24 newTickUpper = _ceil(twapTick + halfWidth, tickSpacing);

        if (newTickLower >= newTickUpper) revert InvalidRange();

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        require(balance0 > 0 || balance1 > 0, "Vault: nothing to mint");

        // Step 6: Mint new position — slippage floor computed on-chain, not caller-supplied.
        _ensureAllowance(token0, address(positionManager), balance0);
        _ensureAllowance(token1, address(positionManager), balance1);

        (uint256 mint0Min, uint256 mint1Min) = _computeMintSlippage(
            newTickLower,
            newTickUpper,
            balance0,
            balance1,
            0
        );

        (uint256 newTokenId, uint128 newLiquidity, , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                tickSpacing: tickSpacing,
                tickLower: newTickLower,
                tickUpper: newTickUpper,
                amount0Desired: balance0,
                amount1Desired: balance1,
                amount0Min: mint0Min,
                amount1Min: mint1Min,
                recipient: address(this),
                deadline: block.timestamp + 300,
                sqrtPriceX96: 0
            })
        );

        if (newLiquidity == 0) revert NoLiquidityMinted();

        // Step 7: Commit
        tokenId = newTokenId;
        rebalanceCount++;

        emit Rebalanced(
            oldTokenId,
            newTokenId,
            newTickLower,
            newTickUpper,
            newLiquidity
        );
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /// @notice Returns current pool price and tick from slot0.
    /// @dev WARNING: slot0 is the instantaneous price and can be manipulated
    ///      within a single block via flash loans. Do NOT use for pricing decisions.
    ///      Use a TWAP oracle for any value-sensitive operations.
    function getPoolState()
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick)
    {
        (sqrtPriceX96, tick, , , , ) = pool.slot0();
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

    function isOutOfRange() external view positionExists returns (bool) {
        (, int24 tick, , , , ) = pool.slot0();
        (, , , , , int24 lo, int24 hi, , , , , ) = positionManager.positions(
            tokenId
        );
        return tick < lo || tick >= hi;
    }

    /// @notice Price of one vault share expressed in token0 units (scaled to 1e18)
    function sharePrice() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        return
            Math.mulDiv(
                _totalVaultValueInToken0(),
                10 ** decimals0,
                supply,
                Math.Rounding.Floor
            );
    }

    /// @notice Returns all key vault metrics in a single call to minimise RPC round-trips.
    function getVaultMetrics()
        external
        view
        returns (
            uint256 tvl,
            int24 tickLower,
            int24 tickUpper,
            uint256 _rebalanceCount,
            uint256 fees0Earned,
            uint256 fees1Earned
        )
    {
        tvl = _totalVaultValueInToken0();
        _rebalanceCount = rebalanceCount;
        fees0Earned = totalFees0Earned;
        fees1Earned = totalFees1Earned;
        if (tokenId != 0) {
            (, , , , , tickLower, tickUpper, , , , , ) = positionManager
                .positions(tokenId);
        }
    }

    /// @dev Remove a proportional fraction (shares/supply) of the active position's liquidity.
    function _removeProportionalLiquidity(
        uint256 shares,
        uint256 supply,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal {
        if (tokenId == 0) return;

        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(
            tokenId
        );

        if (liquidity == 0) return;

        uint128 toRemove = uint128(
            Math.mulDiv(uint256(liquidity), shares, supply, Math.Rounding.Ceil)
        );
        if (toRemove == 0) return;

        positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: toRemove,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: block.timestamp + 300
            })
        );

        positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }

    function _totalVaultValueInToken0() internal view returns (uint256) {
        uint256 bal0 = token0.balanceOf(address(this));
        uint256 bal1 = token1.balanceOf(address(this));

        if (tokenId != 0) {
            (uint256 pos0, uint256 pos1) = _getPositionAmounts();
            // [FIX-6] Also include uncollected fees in the vault valuation
            (uint256 owed0, uint256 owed1) = _getTokensOwed();
            bal0 += pos0 + owed0;
            bal1 += pos1 + owed1;
        }

        return _valueInToken0(bal0, bal1);
    }

    function _valueInToken0(
        uint256 bal0,
        uint256 bal1
    ) internal view returns (uint256) {
        if (bal1 == 0) return bal0;
        return bal0 + _token1ToToken0(bal1);
    }

    function _token1ToToken0(uint256 amount1) internal view returns (uint256) {
        uint160 sqrtPriceX96 = _getTwapSqrtPrice();
        if (sqrtPriceX96 == 0) revert InvalidPoolPrice();
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        // token0 = token1 * 2^192 / sqrtP^2  (sqrtPriceX96 encodes the raw-unit ratio; no decimal correction needed)
        return
            Math.mulDiv(
                amount1,
                uint256(1) << 192,
                Math.mulDiv(sqrtPrice, sqrtPrice, 1)
            );
    }

    function _token0ToToken1(uint256 amount0) internal view returns (uint256) {
        uint160 sqrtPriceX96 = _getTwapSqrtPrice();
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        // token1 = token0 * sqrtP^2 / 2^192  (sqrtPriceX96 encodes the raw-unit ratio; no decimal correction needed)
        uint256 temp = Math.mulDiv(amount0, sqrtPrice, uint256(1) << 96);
        return Math.mulDiv(temp, sqrtPrice, uint256(1) << 96);
    }

    /// @dev Returns (amount0, amount1) of principal locked in the vault's active LP position.
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

        uint160 sqrtPriceX96 = _getTwapSqrtPrice();

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );
    }

    function _getTokensOwed()
        internal
        view
        returns (uint256 owed0, uint256 owed1)
    {
        if (tokenId == 0) return (0, 0);
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
        ) = positionManager.positions(tokenId);
        return (uint256(tokensOwed0), uint256(tokensOwed1));
    }

    function _executeSwap(
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal returns (uint256 amountOut) {
        address tokenIn = zeroForOne ? address(token0) : address(token1);
        address tokenOut = zeroForOne ? address(token1) : address(token0);

        _ensureAllowance(IERC20(tokenIn), address(clSwapRouter), amountIn);

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

    function _deductPerformanceFee(
        uint256 earned0,
        uint256 earned1
    ) internal returns (uint256 fee0, uint256 fee1) {
        if (performanceFeeBps == 0 || feeRecipient == address(0)) return (0, 0);
        fee0 = Math.mulDiv(
            earned0,
            performanceFeeBps,
            10_000,
            Math.Rounding.Ceil
        );
        fee1 = Math.mulDiv(
            earned1,
            performanceFeeBps,
            10_000,
            Math.Rounding.Ceil
        );
        if (fee0 > 0) token0.safeTransfer(feeRecipient, fee0);
        if (fee1 > 0) token1.safeTransfer(feeRecipient, fee1);
    }

    function _ensureAllowance(
        IERC20 token,
        address spender,
        uint256 amount
    ) internal {
        token.forceApprove(spender, amount);
    }

    /// @dev Floor-divide tick by spacing, handling negative ticks correctly.
    function _floor(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 compressed = tick / spacing;
        if (tick < 0 && tick % spacing != 0) compressed--;
        return compressed * spacing;
    }

    /// @dev Ceiling-divide tick by spacing, handling negative ticks correctly.
    function _ceil(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 floored = _floor(tick, spacing);
        return (floored == tick) ? tick : floored + spacing;
    }

    /// @dev Safely read decimals() from a token; defaults to 18 if the call fails.
    function _safeDecimals(address token) internal view returns (uint8) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        if (ok && data.length >= 32) return abi.decode(data, (uint8));
        return 18;
    }

    function _getTwapTick() internal view returns (int24 twapTick) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapSeconds;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);

        int56 delta = tickCumulatives[1] - tickCumulatives[0];
        twapTick = int24(delta / int56(uint56(twapSeconds)));

        (, int24 spotTick, , , , ) = pool.slot0();
        int24 negTwap = -twapTick;
        int256 d1 = int256(twapTick) - int256(spotTick);
        int256 d2 = int256(negTwap) - int256(spotTick);
        if (d1 < 0) d1 = -d1;
        if (d2 < 0) d2 = -d2;
        if (d2 < d1) twapTick = negTwap;
    }

    function _getTwapSqrtPrice() internal view returns (uint160) {
        return TickMath.getSqrtRatioAtTick(_getTwapTick());
    }

    function _isDepositAllowed() internal view returns (bool) {
        if (paused) return false;
        (, int24 spotTick, , , , ) = pool.slot0();
        int24 twapTick = _getTwapTick();
        int256 deviation = int256(spotTick) - int256(twapTick);
        if (deviation < 0) deviation = -deviation;
        return deviation <= int256(uint256(int256(maxTwapDeviationTicks)));
    }

    function _requireSpotNearTwap() internal view {
        (, int24 spotTick, , , , ) = pool.slot0();
        int24 twapTick = _getTwapTick();
        int256 deviation = int256(spotTick) - int256(twapTick);
        if (deviation < 0) deviation = -deviation;
        if (deviation > int256(uint256(int256(maxTwapDeviationTicks))))
            revert PriceDeviatedFromTwap();
    }

    function _computeMintSlippage(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1,
        uint128 liquidity
    ) internal view returns (uint256 min0, uint256 min1) {
        uint160 sqrtTwap = _getTwapSqrtPrice();
        uint160 sqrtLower = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        uint256 exp0;
        uint256 exp1;

        if (liquidity > 0) {
            (exp0, exp1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtTwap,
                sqrtLower,
                sqrtUpper,
                liquidity
            );
        } else {
            uint128 expectedLiq = LiquidityAmounts.getLiquidityForAmounts(
                sqrtTwap,
                sqrtLower,
                sqrtUpper,
                amount0,
                amount1
            );
            (exp0, exp1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtTwap,
                sqrtLower,
                sqrtUpper,
                expectedLiq
            );
        }

        min0 = Math.mulDiv(
            exp0,
            10_000 - slippageBps,
            10_000,
            Math.Rounding.Floor
        );
        min1 = Math.mulDiv(
            exp1,
            10_000 - slippageBps,
            10_000,
            Math.Rounding.Floor
        );
    }

    function _computeRemoveSlippage(
        uint256 shares,
        uint256 supply
    ) internal view returns (uint256 min0, uint256 min1) {
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

        uint128 toRemove = uint128(
            Math.mulDiv(uint256(liquidity), shares, supply, Math.Rounding.Ceil)
        );
        if (toRemove == 0) return (0, 0);

        return _computeMintSlippage(tickLower, tickUpper, 0, 0, toRemove);
    }

    function _computeSwapMinOut(
        uint256 amountIn,
        bool zeroForOne
    ) internal view returns (uint256 minOut) {
        uint256 expected = zeroForOne
            ? _token0ToToken1(amountIn)
            : _token1ToToken0(amountIn);
        minOut = Math.mulDiv(
            expected,
            10_000 - slippageBps,
            10_000,
            Math.Rounding.Floor
        );
    }
}
