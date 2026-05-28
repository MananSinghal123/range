// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../src/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Simulates a CL NonfungiblePositionManager for unit/integration tests.
///      Stores one position per tokenId; minting/burning/collecting are simplified.
contract MockPositionManager is INonfungiblePositionManager {
    using SafeERC20 for IERC20;

    uint256 public nextTokenId = 1;

    struct Position {
        uint96 nonce;
        address operator;
        address token0;
        address token1;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    mapping(uint256 => Position) private _positions;

    // Configurable return values so tests can simulate different scenarios
    uint128 public mintLiquidityReturn = 1e18;
    uint256 public mintAmount0Return;
    uint256 public mintAmount1Return;
    bool public shouldRevertMint;
    bool public shouldRevertDecrease;
    bool public shouldRevertCollect;

    // Track calls for assertions
    uint256 public mintCallCount;
    uint256 public burnCallCount;
    uint256 public collectCallCount;
    uint256 public decreaseLiquidityCallCount;

    // Simulated pending fees to be released on collect
    mapping(uint256 => uint256) public pendingFees0;
    mapping(uint256 => uint256) public pendingFees1;

    function setMintReturn(
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    ) external {
        mintLiquidityReturn = liquidity;
        mintAmount0Return = amount0;
        mintAmount1Return = amount1;
    }

    function setPendingFees(
        uint256 tokenId_,
        uint256 fee0,
        uint256 fee1
    ) external {
        pendingFees0[tokenId_] = fee0;
        pendingFees1[tokenId_] = fee1;
        _positions[tokenId_].tokensOwed0 = uint128(fee0);
        _positions[tokenId_].tokensOwed1 = uint128(fee1);
    }

    function setShouldRevert(
        bool mint_,
        bool decrease_,
        bool collect_
    ) external {
        shouldRevertMint = mint_;
        shouldRevertDecrease = decrease_;
        shouldRevertCollect = collect_;
    }

    function setLiquidity(uint256 tokenId_, uint128 liquidity_) external {
        _positions[tokenId_].liquidity = liquidity_;
    }

    // ── INonfungiblePositionManager ──────────────────────────────────────────

    function positions(
        uint256 tokenId_
    )
        external
        view
        override
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            int24 tickSpacing,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position storage p = _positions[tokenId_];
        return (
            p.nonce,
            p.operator,
            p.token0,
            p.token1,
            p.tickSpacing,
            p.tickLower,
            p.tickUpper,
            p.liquidity,
            p.feeGrowthInside0LastX128,
            p.feeGrowthInside1LastX128,
            p.tokensOwed0,
            p.tokensOwed1
        );
    }

    function mint(
        MintParams calldata params
    )
        external
        payable
        override
        returns (
            uint256 tokenId_,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        if (shouldRevertMint) revert("MockPM: mint reverted");

        tokenId_ = nextTokenId++;
        liquidity = mintLiquidityReturn;
        amount0 = mintAmount0Return;
        amount1 = mintAmount1Return;

        _positions[tokenId_] = Position({
            nonce: 0,
            operator: address(0),
            token0: params.token0,
            token1: params.token1,
            tickSpacing: params.tickSpacing,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: 0,
            feeGrowthInside1LastX128: 0,
            tokensOwed0: 0,
            tokensOwed1: 0
        });

        // Pull tokens from caller (vault)
        if (params.amount0Desired > 0)
            IERC20(params.token0).safeTransferFrom(
                msg.sender,
                address(this),
                params.amount0Desired
            );
        if (params.amount1Desired > 0)
            IERC20(params.token1).safeTransferFrom(
                msg.sender,
                address(this),
                params.amount1Desired
            );

        mintCallCount++;
    }

    function increaseLiquidity(
        IncreaseLiquidityParams calldata params
    )
        external
        payable
        override
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        _positions[params.tokenId].liquidity += uint128(params.amount0Desired);
        return (
            uint128(params.amount0Desired),
            params.amount0Desired,
            params.amount1Desired
        );
    }

    function decreaseLiquidity(
        DecreaseLiquidityParams calldata params
    ) external payable override returns (uint256 amount0, uint256 amount1) {
        if (shouldRevertDecrease) revert("MockPM: decrease reverted");

        Position storage p = _positions[params.tokenId];
        if (params.liquidity > p.liquidity)
            revert("MockPM: insufficient liquidity");

        p.liquidity -= params.liquidity;

        // Simulate proportional token release — naive 1:1 for testing
        amount0 = uint256(params.liquidity);
        amount1 = uint256(params.liquidity);

        // Mark as owed so collect() can release them
        p.tokensOwed0 += uint128(amount0);
        p.tokensOwed1 += uint128(amount1);

        decreaseLiquidityCallCount++;
    }

    function collect(
        CollectParams calldata params
    ) external payable override returns (uint256 amount0, uint256 amount1) {
        if (shouldRevertCollect) revert("MockPM: collect reverted");

        Position storage p = _positions[params.tokenId];

        amount0 = uint256(p.tokensOwed0) > uint256(params.amount0Max)
            ? uint256(params.amount0Max)
            : uint256(p.tokensOwed0);
        amount1 = uint256(p.tokensOwed1) > uint256(params.amount1Max)
            ? uint256(params.amount1Max)
            : uint256(p.tokensOwed1);

        p.tokensOwed0 -= uint128(amount0);
        p.tokensOwed1 -= uint128(amount1);

        if (amount0 > 0)
            IERC20(p.token0).safeTransfer(params.recipient, amount0);
        if (amount1 > 0)
            IERC20(p.token1).safeTransfer(params.recipient, amount1);

        collectCallCount++;
    }

    function burn(uint256 tokenId_) external payable override {
        require(
            _positions[tokenId_].liquidity == 0,
            "MockPM: liquidity not zero"
        );
        require(_positions[tokenId_].tokensOwed0 == 0, "MockPM: tokens owed0");
        require(_positions[tokenId_].tokensOwed1 == 0, "MockPM: tokens owed1");
        delete _positions[tokenId_];
        burnCallCount++;
    }

    function tokenDescriptor() external pure override returns (address) {
        return address(0);
    }

    function owner() external pure override returns (address) {
        return address(0);
    }

    function setTokenDescriptor(address) external override {}

    function setOwner(address) external override {}

    // ── ERC721 stubs ─────────────────────────────────────────────────────────

    function approve(address, uint256) external override {}

    function balanceOf(address) external pure override returns (uint256) {
        return 0;
    }

    function getApproved(uint256) external pure override returns (address) {
        return address(0);
    }

    function isApprovedForAll(address, address) external pure override returns (bool) {
        return false;
    }

    function ownerOf(uint256) external pure override returns (address) {
        return address(0);
    }

    function safeTransferFrom(address, address, uint256) external override {}

    function safeTransferFrom(address, address, uint256, bytes calldata) external {}

    function setApprovalForAll(address, bool) external override {}

    function supportsInterface(bytes4) external pure override returns (bool) {
        return false;
    }

    function tokenByIndex(uint256) external pure override returns (uint256) {
        return 0;
    }

    function tokenOfOwnerByIndex(address, uint256) external pure override returns (uint256) {
        return 0;
    }

    function totalSupply() external pure override returns (uint256) {
        return 0;
    }

    function transferFrom(address, address, uint256) external override {}
}
