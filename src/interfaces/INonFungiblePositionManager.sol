// SPDX-License-Identifier: GPL-2.0-or-later
// Source: Mezo explorer — NonfungiblePositionManager at 0x509Bc221df2B83927c695FA0bb0f5B21053C874c
// Pragma upgraded from =0.7.6 → ^0.8.13 for compatibility with the vault.
// Safe: interfaces are never deployed; they only describe the on-chain ABI.
pragma solidity ^0.8.13;

/// @title INonFungiblePositionManager
/// @notice Wraps CL positions in a non-fungible token interface which allows for them to be
///         transferred and authorized.
/// @dev    Key difference from Uniswap V3: `tickSpacing` (int24) replaces `fee` (uint24)
///         in both MintParams and positions() return values.
interface INonFungiblePositionManager {
    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted when liquidity is increased for a position NFT
    /// @dev Also emitted when a token is minted
    event IncreaseLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when liquidity is decreased for a position NFT
    event DecreaseLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when tokens are collected for a position NFT
    event Collect(
        uint256 indexed tokenId,
        address recipient,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when a new Token Descriptor is set
    event TokenDescriptorChanged(address indexed tokenDescriptor);

    /// @notice Emitted when a new Owner is set
    event TransferOwnership(address indexed owner);

    // ─── Structs ──────────────────────────────────────────────────────────────

    struct MintParams {
        address token0;
        address token1;
        int24 tickSpacing; // Mezo: int24 tickSpacing (Uniswap V3 has uint24 fee here)
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
        uint160 sqrtPriceX96; // Mezo addition: initial sqrt price — pass 0 if pool already exists
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    // ─── Position Query ───────────────────────────────────────────────────────

    /// @notice Returns the position information associated with a given token ID.
    /// @dev Throws if the token ID is not valid.
    /// @param tokenId                     The ID of the token that represents the position
    /// @return nonce                      The nonce for permits
    /// @return operator                   The address approved for spending
    /// @return token0                     The address of token0 for the pool
    /// @return token1                     The address of token1 for the pool
    /// @return tickSpacing                Tick spacing of the pool (replaces fee in Uniswap V3)
    /// @return tickLower                  Lower end of the tick range
    /// @return tickUpper                  Upper end of the tick range
    /// @return liquidity                  Liquidity of the position
    /// @return feeGrowthInside0LastX128   Fee growth of token0 since last position action
    /// @return feeGrowthInside1LastX128   Fee growth of token1 since last position action
    /// @return tokensOwed0                Uncollected token0 fees owed to position
    /// @return tokensOwed1                Uncollected token1 fees owed to position
    function positions(
        uint256 tokenId
    )
        external
        view
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
        );

    // ─── Core Liquidity Functions ─────────────────────────────────────────────

    /// @notice Creates a new position wrapped in an NFT.
    ///         The pool must already exist and be initialized.
    ///         Pass sqrtPriceX96 = 0 if the pool is already initialized.
    /// @return tokenId   The ID of the NFT representing the minted position
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0   The amount of token0 deposited
    /// @return amount1   The amount of token1 deposited
    function mint(
        MintParams calldata params
    )
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    /// @notice Increases the amount of liquidity in a position, with tokens paid by msg.sender
    /// @return liquidity The new liquidity amount as a result of the increase
    /// @return amount0   The amount of token0 used to achieve resulting liquidity
    /// @return amount1   The amount of token1 used to achieve resulting liquidity
    function increaseLiquidity(
        IncreaseLiquidityParams calldata params
    )
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Decreases the amount of liquidity in a position and accounts it to the position
    /// @return amount0 The amount of token0 accounted to tokens owed
    /// @return amount1 The amount of token1 accounted to tokens owed
    function decreaseLiquidity(
        DecreaseLiquidityParams calldata params
    ) external payable returns (uint256 amount0, uint256 amount1);

    /// @notice Collects up to a maximum amount of fees owed to a specific position to the recipient
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collect(
        CollectParams calldata params
    ) external payable returns (uint256 amount0, uint256 amount1);

    /// @notice Burns a token ID, deleting it from the NFT contract.
    ///         The token must have 0 liquidity and all tokens must be collected first.
    function burn(uint256 tokenId) external payable;

    // ─── Admin / Descriptor ───────────────────────────────────────────────────

    /// @notice Returns the address of the Token Descriptor (handles tokenURI generation)
    function tokenDescriptor() external view returns (address);

    /// @notice Returns the address of the contract Owner
    function owner() external view returns (address);

    /// @notice Sets a new Token Descriptor
    function setTokenDescriptor(address _tokenDescriptor) external;

    /// @notice Sets a new Owner address
    function setOwner(address _owner) external;

    // ─── ERC-721 ──────────────────────────────────────────────────────────────

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
    function tokenOfOwnerByIndex(
        address owner,
        uint256 index
    ) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function tokenByIndex(uint256 index) external view returns (uint256);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(
        address owner,
        address operator
    ) external view returns (bool);
    function setApprovalForAll(address operator, bool approved) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
