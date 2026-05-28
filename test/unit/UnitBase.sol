// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../BaseTest.sol";

/// @dev Shared helpers for all unit test contracts.
abstract contract UnitBase is BaseTest {
    function setUp() public virtual override {
        super.setUp();
        address etchedPm = address(vault.positionManager());
        address etchedRouter = address(vault.clSwapRouter());
        // vm.etch copies bytecode but NOT storage. Three fixes for PM:
        // 1. nextTokenId (slot 0) defaults to 0 → mint() returns tokenId=0 → NotInitialized
        vm.store(etchedPm, bytes32(0), bytes32(uint256(1)));
        // 2. mintLiquidityReturn defaults to 0 → NoLiquidityMinted
        _pm().setMintReturn(1e18, 0, 0);
        // 3. Token balances at etched addresses are 0 (tokens were minted to the deployed mocks)
        token0.mint(etchedPm, 100e8);
        token1.mint(etchedPm, 1e25);
        token0.mint(etchedRouter, 100e8);
        token1.mint(etchedRouter, 1e25);
    }

    function _pm() internal view returns (MockPositionManager) {
        return MockPositionManager(address(vault.positionManager()));
    }

    /// @dev Initialises a position with a small liquidity value so that
    ///      decreaseLiquidity never tries to release more tokens than the
    ///      mock PM holds.
    function _initSmallPosition(int24 lo, int24 hi) internal {
        _pm().setMintReturn(1e6, 0, 0);
        _initPosition(lo, hi, 5e7, 0);
        _pm().setMintReturn(1e18, 0, 0);
    }
}
