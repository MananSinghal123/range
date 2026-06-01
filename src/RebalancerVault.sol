// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {ICLSwapRouter} from "./interfaces/router/ICLSwapRouter.sol";
import {ICLPool} from "./interfaces/pool/ICLPool.sol";

/// @dev COMPILE-ONLY STUB — replaced by RebalancerVaultUpgradeable.
///      Exists so legacy test imports continue to parse during the transition.
///      All functions revert at runtime. Removed in the test-cutover task (Task 18).
contract RebalancerVault {
    enum StrategyType { TIGHT, MEDIUM, WIDE }

    uint256 public constant DEAD_SHARES = 1_000;

    // Errors (referenced by tests via RebalancerVault.ErrorName.selector)
    error TimelockActive();
    error SameBlock();
    error NotOwner();
    error NotOperator();
    error ZeroAddress();
    error ZeroAmount();
    error BelowMinDeposit();
    error NoAssets();
    error ExceedsMaxDeposit();
    error ExceedsMaxMint();
    error ExceedsMaxWithdraw();
    error ExceedsMaxRedeem();
    error NoLiquidityMinted();
    error AlreadyInitialized();
    error NotInitialized();
    error InvalidRange();
    error NothingToMint();
    error FeeTooHigh();
    error SameOwner();
    error NotPendingOwner();
    error InvalidToken();
    error PriceDeviatedFromTwap();

    // State vars matching the old monolith public surface.
    address public owner;
    address public pendingOwner;
    address public operator;
    bool    public paused;
    uint256 public tokenId;
    uint256 public rebalanceCount;
    uint256 public totalFees0Earned;
    uint256 public totalFees1Earned;
    uint256 public performanceFeeBps;
    address public feeRecipient;
    uint256 public pendingFeeBps;
    address public pendingFeeRecipient;
    uint256 public feeChangeActiveAt;
    uint32  public twapSeconds;
    int24   public maxTwapDeviationTicks;
    uint256 public slippageBps;
    mapping(StrategyType => int24) public strategyWidths;

    // These match the old constant addresses but are set to zero — tests that
    // call vm.etch(address(vault.positionManager()), ...) will etch to address(0).
    INonfungiblePositionManager public constant positionManager =
        INonfungiblePositionManager(address(0));
    ICLSwapRouter public constant clSwapRouter =
        ICLSwapRouter(address(0));

    constructor(
        address /*_owner*/,
        address /*_pool*/,
        address /*_operator*/,
        string memory /*_name*/,
        string memory /*_symbol*/
    ) {
        revert("RebalancerVault: replaced by RebalancerVaultUpgradeable");
    }

    // ERC20/ERC4626
    function totalSupply()   external pure returns (uint256) { revert("stub"); }
    function balanceOf(address) external pure returns (uint256) { revert("stub"); }
    function totalAssets()   external pure returns (uint256) { revert("stub"); }
    function decimals()      external pure returns (uint8)   { revert("stub"); }
    function name()          external pure returns (string memory) { revert("stub"); }
    function symbol()        external pure returns (string memory) { revert("stub"); }
    function asset()         external pure returns (address)  { revert("stub"); }
    function approve(address, uint256) external pure returns (bool) { revert("stub"); }
    function allowance(address, address) external pure returns (uint256) { revert("stub"); }
    function transfer(address, uint256) external pure returns (bool) { revert("stub"); }
    function transferFrom(address, address, uint256) external pure returns (bool) { revert("stub"); }

    // Token/pool accessors
    function token0() external pure returns (IERC20)  { revert("stub"); }
    function token1() external pure returns (IERC20)  { revert("stub"); }
    function pool()   external pure returns (ICLPool) { revert("stub"); }

    // ERC4626 deposits/withdrawals
    function previewDeposit(uint256) external pure returns (uint256) { revert("stub"); }
    function previewMint(uint256)    external pure returns (uint256) { revert("stub"); }
    function previewWithdraw(uint256) external pure returns (uint256) { revert("stub"); }
    function previewRedeem(uint256)  external pure returns (uint256) { revert("stub"); }
    function maxDeposit(address)     external pure returns (uint256) { revert("stub"); }
    function maxMint(address)        external pure returns (uint256) { revert("stub"); }
    function maxWithdraw(address)    external pure returns (uint256) { revert("stub"); }
    function maxRedeem(address)      external pure returns (uint256) { revert("stub"); }
    function deposit(uint256, address) external pure returns (uint256) { revert("stub"); }
    function mint(uint256, address)  external pure returns (uint256) { revert("stub"); }
    function withdraw(uint256, address, address) external pure returns (uint256) { revert("stub"); }
    function redeem(uint256, address, address)   external pure returns (uint256) { revert("stub"); }

    // Vault-specific
    function depositToken1(uint256, address) external pure returns (uint256) { revert("stub"); }
    function previewDepositToken1(uint256)   external pure returns (uint256) { revert("stub"); }
    function convertToShares(uint256) external pure returns (uint256) { revert("stub"); }
    function convertToAssets(uint256) external pure returns (uint256) { revert("stub"); }

    // Position
    function initializePosition(int24, int24, uint256, uint256, uint256, uint256) external pure { revert("stub"); }
    function collectFees(uint256, uint256) external pure returns (uint256, uint256) { revert("stub"); }
    function rebalance(bool, uint256, StrategyType) external pure { revert("stub"); }
    function computeRebalanceParams(StrategyType) external pure returns (bool, uint256) { revert("stub"); }
    function getPosition() external pure returns (address, address, int24, int24, int24, uint128) { revert("stub"); }
    function isOutOfRange() external pure returns (bool) { revert("stub"); }
    function getPoolState() external pure returns (uint160, int24) { revert("stub"); }

    // Admin
    function transferOwnership(address)              external pure { revert("stub"); }
    function acceptOwnership()                       external pure { revert("stub"); }
    function setOperator(address)                    external pure { revert("stub"); }
    function setPaused(bool)                         external pure { revert("stub"); }
    function proposePerformanceFee(uint256, address) external pure { revert("stub"); }
    function applyPerformanceFee()                   external pure { revert("stub"); }
    function sweepToken(address, address)            external pure { revert("stub"); }
    function setStrategyWidth(StrategyType, int24)   external pure { revert("stub"); }
    function setTwapSeconds(uint32)                  external pure { revert("stub"); }
    function setMaxTwapDeviationTicks(int24)         external pure { revert("stub"); }
    function setSlippageBps(uint256)                 external pure { revert("stub"); }
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) { revert("stub"); }
    receive() external payable {}
}
