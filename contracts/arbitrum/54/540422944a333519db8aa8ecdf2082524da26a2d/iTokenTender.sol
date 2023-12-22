// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface iTokenTender {
    /**
     * @notice Calculates the exchange rate from the underlying to the CToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateStored() external view returns (uint256);
}

