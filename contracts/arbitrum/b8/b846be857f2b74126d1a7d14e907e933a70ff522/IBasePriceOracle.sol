// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IERC20Upgradeable.sol";

interface IBasePriceOracle {
    /**
     * @notice Get the price of an underlying asset.
     * @param underlying The underlying asset to get the price of.
     * @return The underlying asset price in ETH as a mantissa (scaled by 1e18).
     * Zero means the price is unavailable.
     */
    function getPrice(address underlying) external returns (uint256);
}

