// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library VaultStorageLib {
    /// @custom:storage-location erc7201:mezo.storage.RebalancerVault
    struct VaultStorage {
        address owner;
        address pendingOwner;
        address operator;
        address guardian;
        bool paused;
        address strategy;
        address dexAdapter;
        address pool;
        address token0;
        address token1;
        uint8 decimals0;
        uint8 decimals1;
        address positionManager;
        address swapRouter;
        uint256 tokenId;
        uint256 performanceFeeBps;
        address feeRecipient;
        uint256 pendingFeeBps;
        address pendingFeeRecipient;
        uint256 feeChangeActiveAt;
        uint256 rebalanceCount;
        uint256 totalFees0Earned;
        uint256 totalFees1Earned;
        uint32 twapSeconds;
        int24 maxTwapDeviationTicks;
        uint256 slippageBps;
        mapping(address => uint256) lastDepositBlock;
    }

    function STORAGE_SLOT() internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    uint256(keccak256("mezo.storage.RebalancerVault")) - 1
                )
            ) & ~bytes32(uint256(0xff));
    }

    function get() internal pure returns (VaultStorage storage $) {
        bytes32 slot = STORAGE_SLOT();
        assembly {
            $.slot := slot
        }
    }
}
