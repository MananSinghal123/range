// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IStrategy} from "./interfaces/IStrategy.sol";
import {VaultMath} from "../libraries/VaultMath.sol";

contract Strategy is IStrategy {
    int24 public immutable halfWidth;

    error NonPositiveWidth();

    constructor(int24 _halfWidth) {
        if (_halfWidth <= 0) revert NonPositiveWidth();
        halfWidth = _halfWidth;
    }

    /// @inheritdoc IStrategy
    function computeRange(
        int24 twapTick,
        int24 tickSpacing
    ) external view returns (int24 tickLower, int24 tickUpper) {
        tickLower = VaultMath.floor(twapTick - halfWidth, tickSpacing);
        tickUpper = VaultMath.ceil(twapTick + halfWidth, tickSpacing);
    }

    /// @inheritdoc IStrategy
    function computeOptimalSwap(
        uint160 sqrtP,
        uint160 sqrtA,
        uint160 sqrtB,
        uint256 bal0,
        uint256 bal1
    ) external pure returns (bool zeroForOne, uint256 amount) {
        return VaultMath.computeOptimalSwap(sqrtP, sqrtA, sqrtB, bal0, bal1);
    }
}
