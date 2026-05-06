// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

//  RebalancerVault — Automated LP Rebalancing Vault for Mezo DEX
//  Compatible with Mezo's CL (Uniswap V3 fork using tickSpacing instead of fee)

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "./interfaces/INonFungiblePositionManager.sol";
import "./interfaces/ICLSwapRouter.sol";
import "./interfaces/ICLPool.sol";

contract RebalancerVault is ERC20, ReentrancyGuard, IERC4626 {
    using SafeERC20 for IERC20;

    INonFungiblePositionManager public constant positionManager =
        INonFungiblePositionManager(0x509Bc221df2B83927c695FA0bb0f5B21053C874c);
    ICLSwapRouter public constant clSwapRouter =
        ICLSwapRouter(0x37cDd11919ec3860eaD9efB8673d7476E5326225);

    address public owner;
    address public pendingOwner;
    address public operator;
    bool public paused;

    /// @notice Performance fee in bps charged on earned LP fees only (max 1000 = 10%)
    uint256 public performanceFeeBps;
    address public feeRecipient;

    /// @notice Pending performance fee configuration waiting for timelock
    uint256 public pendingFeeBps;
    address public pendingFeeRecipient;
    /// @notice Timestamp when pending fee change becomes active
    uint256 public feeChangeActiveAt;

    // ─── Pool & Token State ───────────────────────────────────────────────────
    ICLPool public immutable pool;

    /// @notice token0 is the ERC-4626 "asset". token1 accepted via depositToken1().
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    /// @dev Cached token decimals for price-normalisation (e.g. BTC=8, MUSD=18)
    uint8 public immutable decimals0;
    uint8 public immutable decimals1;

    /// @notice Active LP position NFT tokenId (0 = vault not yet initialised)
    uint256 public tokenId;

    // ─── Inflation-Attack Guard ───────────────────────────────────────────────
    /// @dev Minted to address(0xdead) on first deposit; makes share-price donation attacks
    ///      uneconomical. See ERC-4626 Security Considerations.
    uint256 public constant DEAD_SHARES = 1_000;

    // ─── Events ───────────────────────────────────────────────────────────────
    /// @notice Emitted when token1 is deposited via the non-standard depositToken1() path
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
    error ExceedsMaxDeposit();
    error ExceedsMaxMint();
    error ExceedsMaxWithdraw();
    error ExceedsMaxRedeem();
    error SameOwner();
    error NotPendingOwner();
    error InsufficientToken0ForWithdraw(uint256 available, uint256 required);
    error TimelockActive();

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
    ) ERC20(_name, _symbol) {
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
    }

    //to-be-audited
    function decimals() public view override(ERC20, IERC4626) returns (uint8) {
        return decimals0;
    }

    //audited
    function asset() public view override returns (address assetTokenAddress) {
        return address(token0);
    }

    //audited
    function totalAssets()
        public
        view
        override
        returns (uint256 totalManagedAssets)
    {
        return _totalVaultValueInToken0();
    }

    //audited
    function convertToShares(
        uint256 assets
    ) public view override returns (uint256 shares) {
        uint256 supply = totalSupply();
        uint256 ta = totalAssets();
        // Guard: if supply > 0 but total assets wiped out, return 0
        // instead of reverting — upholds MUST NOT revert requirement.
        if (supply == 0) return assets;
        if (ta == 0) return 0;
        return FullMath.mulDiv(assets, supply, ta);
    }

    //audited
    function convertToAssets(
        uint256 shares
    ) public view override returns (uint256 assets) {
        uint256 supply = totalSupply();
        return
            supply == 0
                ? shares
                : FullMath.mulDiv(shares, totalAssets(), supply);
    }

    //audited
    /// @inheritdoc IERC4626
    function maxDeposit(
        address /*receiver*/
    ) public view override returns (uint256 maxAssets) {
        return paused ? 0 : type(uint256).max;
    }

    //to-be-audited
    /// @inheritdoc IERC4626
    function previewDeposit(
        uint256 assets
    ) public view override returns (uint256 shares) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return assets > DEAD_SHARES ? assets - DEAD_SHARES : 0;
        }
        uint256 ta = totalAssets();
        return ta == 0 ? 0 : FullMath.mulDiv(assets, supply, ta);
    }

    //to-be-audited
    /// @inheritdoc IERC4626
    function deposit(
        uint256 assets,
        address receiver
    ) public override whenNotPaused nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (assets > maxDeposit(receiver)) revert ExceedsMaxDeposit();

        uint256 totalValBefore = _totalVaultValueInToken0();
        uint256 supply = totalSupply();

        token0.safeTransferFrom(msg.sender, address(this), assets);

        if (supply == 0) {
            if (assets <= DEAD_SHARES) revert BelowMinDeposit();
            _mint(address(0xdead), DEAD_SHARES);
            shares = assets - DEAD_SHARES;
        } else {
            if (totalValBefore == 0) revert NoAssets();
            shares = FullMath.mulDiv(assets, supply, totalValBefore);
        }

        if (shares == 0) revert ZeroAmount();
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    //audited
    /// @inheritdoc IERC4626
    function maxMint(
        address /*receiver*/
    ) public view override returns (uint256 maxShares) {
        return paused ? 0 : type(uint256).max;
    }

    //to-be-audited
    /// @inheritdoc IERC4626
    /// @dev Rounds UP per spec — vault collects at least enough assets for the shares.
    function previewMint(
        uint256 shares
    ) public view override returns (uint256 assets) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return shares + DEAD_SHARES;
        }
        uint256 ta = totalAssets();
        if (ta == 0) return shares;
        assets = FullMath.mulDiv(shares, ta, supply);
        if (FullMath.mulDiv(assets, supply, ta) < shares) assets += 1;
    }

    //to-be-audited
    /// @inheritdoc IERC4626
    function mint(
        uint256 shares,
        address receiver
    ) public override whenNotPaused nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (shares > maxMint(receiver)) revert ExceedsMaxMint();

        // Compute exact assets to pull (rounds UP so vault is fully collateralised)
        assets = previewMint(shares);
        if (assets == 0) revert ZeroAmount();

        uint256 supply = totalSupply();

        token0.safeTransferFrom(msg.sender, address(this), assets);

        if (supply == 0) {
            _mint(address(0xdead), DEAD_SHARES);
        }

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    //audited
    /// @inheritdoc IERC4626
    function maxWithdraw(
        address owner_
    ) public view override returns (uint256 maxAssets) {
        if (paused) return 0;
        return convertToAssets(balanceOf(owner_));
    }

    //to-be-audited
    /// @inheritdoc IERC4626
    /// @dev Rounds UP per spec (vault-favoured — burns slightly more shares from withdrawer).
    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256 shares) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        uint256 ta = totalAssets();
        if (ta == 0) return 0;
        shares = FullMath.mulDiv(assets, supply, ta);
        if (FullMath.mulDiv(shares, ta, supply) < assets) shares += 1;
    }

    //to-be-audited
    /// @inheritdoc IERC4626
    function withdraw(
        uint256 assets,
        address receiver,
        address owner_
    ) public override whenNotPaused nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (assets > maxWithdraw(owner_)) revert ExceedsMaxWithdraw();

        shares = previewWithdraw(assets);
        if (shares == 0) revert ZeroAmount();

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, shares);
        }

        uint256 supply = totalSupply();

        // Remove proportional LP liquidity to free idle tokens
        _removeProportionalLiquidity(shares, supply, 0, 0);

        uint256 idle0 = token0.balanceOf(address(this));
        if (idle0 < assets) {
            // Swap the minimum token1 required to cover the shortfall
            uint256 shortfall = assets - idle0;
            // Convert shortfall from token0 terms to token1 terms
            uint256 token1Needed = _token0ToToken1(shortfall);
            uint256 available1 = token1.balanceOf(address(this));
            // Cap at available token1 to avoid over-selling
            if (token1Needed > available1) token1Needed = available1;
            if (token1Needed > 0) {
                _ensureAllowance(token1, address(clSwapRouter), token1Needed);
                _executeSwap(false, token1Needed, 0); // sell token1 for token0
            }
        }

        uint256 finalIdle0 = token0.balanceOf(address(this));
        if (finalIdle0 < assets)
            revert InsufficientToken0ForWithdraw(finalIdle0, assets);

        _burn(owner_, shares);

        token0.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    //audited
    /// @inheritdoc IERC4626
    function maxRedeem(
        address owner_
    ) public view override returns (uint256 maxShares) {
        return paused ? 0 : balanceOf(owner_);
    }

    /// @inheritdoc IERC4626
    /// @dev Rounds DOWN per spec (mulDiv floors) — caller gets no more than their fair share.
    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256 assets) {
        return convertToAssets(shares);
    }

    //to-be-audited
    /// @inheritdoc IERC4626
    function redeem(
        uint256 shares,
        address receiver,
        address owner_
    ) public override whenNotPaused nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (shares > maxRedeem(owner_)) revert ExceedsMaxRedeem();

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, shares);
        }

        uint256 supply = totalSupply();

        // [FIX-3] Snapshot balances BEFORE LP removal
        uint256 idleBefore0 = token0.balanceOf(address(this));
        uint256 idleBefore1 = token1.balanceOf(address(this));

        // Remove proportional LP liquidity so freed tokens land in idle balances
        _removeProportionalLiquidity(shares, supply, 0, 0);

        // Tokens freed from LP
        uint256 freed0 = token0.balanceOf(address(this)) - idleBefore0;
        uint256 freed1 = token1.balanceOf(address(this)) - idleBefore1;

        // Proportional share of pre-existing idle (round down — vault-favoured)
        uint256 idleShare0 = FullMath.mulDiv(idleBefore0, shares, supply);
        uint256 idleShare1 = FullMath.mulDiv(idleBefore1, shares, supply);

        uint256 amount0 = freed0 + idleShare0;
        uint256 amount1 = freed1 + idleShare1;

        // Burn AFTER computing amounts so supply is still the pre-burn value
        _burn(owner_, shares);

        if (amount0 > 0) token0.safeTransfer(receiver, amount0);
        if (amount1 > 0) token1.safeTransfer(receiver, amount1);

        assets = amount0;

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    function depositToken1(
        uint256 token1Amount,
        address receiver
    ) external whenNotPaused nonReentrant returns (uint256 shares) {
        if (token1Amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

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
            shares = FullMath.mulDiv(depositValToken0, supply, totalValBefore);
        }

        if (shares == 0) revert ZeroAmount();
        _mint(receiver, shares);

        emit Token1Deposited(msg.sender, receiver, token1Amount, shares);
    }

    /// @param shares           Exact vault shares to burn
    /// @param receiver         Address that receives the tokens
    /// @param owner_           Address whose shares are burned
    /// @param amount0MinRedeem Minimum token0 from decreaseLiquidity (slippage guard)
    /// @param amount1MinRedeem Minimum token1 from decreaseLiquidity (slippage guard)
    /// @return amount0         Token0 sent to receiver
    /// @return amount1         Token1 sent to receiver
    function redeemWithSlippage(
        uint256 shares,
        address receiver,
        address owner_,
        uint256 amount0MinRedeem,
        uint256 amount1MinRedeem
    )
        external
        whenNotPaused
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (shares > maxRedeem(owner_)) revert ExceedsMaxRedeem();

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, shares);
        }

        uint256 supply = totalSupply();

        // [FIX-3] Snapshot balances before LP removal (same fix as redeem())
        uint256 idleBefore0 = token0.balanceOf(address(this));
        uint256 idleBefore1 = token1.balanceOf(address(this));

        _removeProportionalLiquidity(
            shares,
            supply,
            amount0MinRedeem,
            amount1MinRedeem
        );

        uint256 freed0 = token0.balanceOf(address(this)) - idleBefore0;
        uint256 freed1 = token1.balanceOf(address(this)) - idleBefore1;

        uint256 idleShare0 = FullMath.mulDiv(idleBefore0, shares, supply);
        uint256 idleShare1 = FullMath.mulDiv(idleBefore1, shares, supply);

        amount0 = freed0 + idleShare0;
        amount1 = freed1 + idleShare1;

        _burn(owner_, shares);

        if (amount0 > 0) token0.safeTransfer(receiver, amount0);
        if (amount1 > 0) token1.safeTransfer(receiver, amount1);

        uint256 totalAssetsRedeemed = amount0 + _token1ToToken0(amount1);
        emit Withdraw(
            msg.sender,
            receiver,
            owner_,
            totalAssetsRedeemed,
            shares
        );
    }

    //audited
    function transferOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert ZeroAddress();
        if (_newOwner == owner) revert SameOwner();
        pendingOwner = _newOwner;
        emit OwnershipTransferStarted(owner, _newOwner);
    }

    //audited
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }
    //audited
    function setOperator(address _operator) external onlyOwner {
        if (_operator == address(0)) revert ZeroAddress();
        operator = _operator;
        emit OperatorUpdated(_operator);
    }

    //audited
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit VaultPaused(_paused);
    }

    //audited
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
            INonFungiblePositionManager.MintParams({
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
            INonFungiblePositionManager.DecreaseLiquidityParams({
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
            INonFungiblePositionManager.CollectParams({
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

        if (fee0 > 0 || fee1 > 0) emit FeesCollected(fee0, fee1, feeRecipient);
    }

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

        // Step 1: Remove all liquidity
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

        // Step 2: Performance fee on earned fees only
        (uint256 fee0, uint256 fee1) = _deductPerformanceFee(
            uint256(tokensOwed0),
            uint256(tokensOwed1)
        );
        if (fee0 > 0 || fee1 > 0) emit FeesCollected(fee0, fee1, feeRecipient);

        // Step 3: Burn old NFT
        positionManager.burn(oldTokenId);

        // Step 4: Optional swap to rebalance token ratio
        if (swapAmount > 0) {
            _executeSwap(swapZeroForOne, swapAmount, swapAmountOutMin);
        }

        // Step 5: Compute new range centred on current tick
        (, int24 currentTick, , , , ) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        int24 halfWidth = (tickUpper - tickLower) / 2;

        int24 newTickLower = _floor(currentTick - halfWidth, tickSpacing);
        int24 newTickUpper = _ceil(currentTick + halfWidth, tickSpacing);

        if (newTickLower >= newTickUpper) revert InvalidRange();

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        require(balance0 > 0 || balance1 > 0, "Vault: nothing to mint");

        // Step 6: Mint new position
        _ensureAllowance(token0, address(positionManager), balance0);
        _ensureAllowance(token1, address(positionManager), balance1);

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
                deadline: block.timestamp + 300,
                sqrtPriceX96: 0
            })
        );

        if (newLiquidity == 0) revert NoLiquidityMinted();

        // Step 7: Commit
        tokenId = newTokenId;

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
        return FullMath.mulDiv(_totalVaultValueInToken0(), 1e18, supply);
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
            FullMath.mulDiv(uint256(liquidity), shares, supply)
        );
        if (toRemove == 0) return;

        positionManager.decreaseLiquidity(
            INonFungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: toRemove,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
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

    //audited
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

        (uint160 sqrtPriceX96, , , , , ) = pool.slot0();

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

        if (decimals1 > decimals0) {
            val1InToken0 /= 10 ** uint256(decimals1 - decimals0);
        } else if (decimals0 > decimals1) {
            val1InToken0 *= 10 ** uint256(decimals0 - decimals1);
        }

        return bal0 + val1InToken0;
    }

    function _token1ToToken0(uint256 amount1) internal view returns (uint256) {
        (uint160 sqrtPriceX96, , , , , ) = pool.slot0();
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
            result /= 10 ** uint256(decimals1 - decimals0);
        } else if (decimals0 > decimals1) {
            result *= 10 ** uint256(decimals0 - decimals1);
        }
        return result;
    }

    function _token0ToToken1(uint256 amount0) internal view returns (uint256) {
        (uint160 sqrtPriceX96, , , , , ) = pool.slot0();

        uint256 temp = FullMath.mulDiv(
            amount0,
            uint256(1) << 96,
            uint256(sqrtPriceX96)
        );
        uint256 result = FullMath.mulDiv(
            temp,
            uint256(1) << 96,
            uint256(sqrtPriceX96)
        );
        if (decimals0 > decimals1) {
            result /= 10 ** uint256(decimals0 - decimals1);
        } else if (decimals1 > decimals0) {
            result *= 10 ** uint256(decimals1 - decimals0);
        }
        return result;
    }

    // audited
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

        (uint160 sqrtPriceX96, , , , , ) = pool.slot0();

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );
    }

    //audited
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

        // [FIX-9] Grant allowance just-in-time
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
        fee0 = FullMath.mulDiv(earned0, performanceFeeBps, 10_000);
        fee1 = FullMath.mulDiv(earned1, performanceFeeBps, 10_000);
        if (fee0 > 0) token0.safeTransfer(feeRecipient, fee0);
        if (fee1 > 0) token1.safeTransfer(feeRecipient, fee1);
    }

    function _ensureAllowance(
        IERC20 token,
        address spender,
        uint256 amount
    ) internal {
        uint256 current = token.allowance(address(this), spender);
        if (current < amount) {
            // For tokens like USDT that require resetting to 0 first
            if (current > 0) {
                token.safeDecreaseAllowance(spender, current);
            }
            token.safeIncreaseAllowance(spender, amount);
        }
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
}
