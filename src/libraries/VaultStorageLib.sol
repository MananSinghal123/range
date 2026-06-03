// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title VaultStorageLib
/// @notice ERC-7201 namespaced storage for RebalancerVaultUpgradeable custom state.
///         Keeping all bespoke vault state in one explicitly-located struct prevents
///         layout collisions across upgrades and with OZ base-contract namespaces.
library VaultStorageLib {
    /// @custom:storage-location erc7201:mezo.storage.RebalancerVault
    struct VaultStorage {
        // ── access control / lifecycle ──
        address owner;
        address pendingOwner;
        address operator;
        address guardian;          // factory-set; may pause (pause-all support)
        bool paused;
        // ── swappable modules + their timelocks ──
        address strategy;
        address dexAdapter;
        // ── DEX wiring (was immutable / constant in the monolith) ──
        address pool;
        address token0;
        address token1;
        uint8 decimals0;
        uint8 decimals1;
        address positionManager;   // was `constant`
        address swapRouter;        // was `constant`
        // ── position ──
        uint256 tokenId;
        // ── fees (+ 2-day timelock) ──
        uint256 performanceFeeBps;
        address feeRecipient;
        uint256 pendingFeeBps;
        address pendingFeeRecipient;
        uint256 feeChangeActiveAt;
        // ── accounting / stats ──
        uint256 rebalanceCount;
        uint256 totalFees0Earned;
        uint256 totalFees1Earned;
        // ── oracle / guard params ──
        uint32 twapSeconds;
        int24 maxTwapDeviationTicks;
        uint256 slippageBps;
        // ── guards ──
        mapping(address => uint256) lastDepositBlock;
    }

    // keccak256(abi.encode(uint256(keccak256("mezo.storage.RebalancerVault")) - 1)) & ~bytes32(uint256(0xff))
    /// @notice The fixed ERC-7201 base slot for the vault namespace.
    function STORAGE_SLOT() internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(uint256(keccak256("mezo.storage.RebalancerVault")) - 1)
            ) & ~bytes32(uint256(0xff));
    }

    /// @notice Returns a storage pointer to the namespaced VaultStorage struct.
    function get() internal pure returns (VaultStorage storage $) {
        bytes32 slot = STORAGE_SLOT();
        assembly {
            $.slot := slot
        }
    }
}
