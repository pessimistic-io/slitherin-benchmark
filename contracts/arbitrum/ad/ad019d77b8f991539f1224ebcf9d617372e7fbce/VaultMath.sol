// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

/// @title VaultMath
/// @author Umami DAO
library VaultMath {
    uint256 constant SCALE = 1e30;
    uint256 constant BIPS = 10_000;

    /**
     * @notice Returns a slippage adjusted amount for calculations where slippage is accounted
     * @param amount of the asset
     * @param slippage %
     * @return value of the slippage adjusted amount
     */
    function getSlippageAdjustedAmount(uint256 amount, uint256 slippage) internal pure returns (uint256) {
        return (amount * (1 * SCALE - slippage)) / SCALE;
    }
}

