// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPriceOracle {
    /**
     * @notice Get the underlying price of a fToken asset
     * @param _fToken Address of the fToken to get the underlying price of
     * @return The underlying asset price mantissa (scaled by 1e18).
     *  Zero means the price is unavailable.
     */
    function getUnderlyingPrice(address _fToken) external view returns (uint256);
}

