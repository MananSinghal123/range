// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./RebalancerVault.sol";

/// @notice Read-only helper that bundles vault view calls to reduce RPC round-trips.
///         Kept separate so convenience functions don't count toward the vault's
///         EIP-170 bytecode limit.
contract VaultLens {
    /// @notice Price of one vault share expressed in token0 units (scaled to token0 decimals).
    function sharePrice(address vault) external view returns (uint256) {
        RebalancerVault v = RebalancerVault(payable(vault));
        uint256 supply = v.totalSupply();
        if (supply == 0) return 0;
        return Math.mulDiv(
            v.totalAssets(),
            10 ** v.decimals(),
            supply,
            Math.Rounding.Floor
        );
    }

    /// @notice Returns all key vault metrics in a single call.
    function getVaultMetrics(address vault)
        external
        view
        returns (
            uint256 tvl,
            int24 tickLower,
            int24 tickUpper,
            uint256 rebalanceCount,
            uint256 fees0Earned,
            uint256 fees1Earned
        )
    {
        RebalancerVault v = RebalancerVault(payable(vault));
        tvl          = v.totalAssets();
        rebalanceCount = v.rebalanceCount();
        fees0Earned  = v.totalFees0Earned();
        fees1Earned  = v.totalFees1Earned();

        if (v.tokenId() != 0) {
            (, , , tickLower, tickUpper, ) = v.getPosition();
        }
    }
}
