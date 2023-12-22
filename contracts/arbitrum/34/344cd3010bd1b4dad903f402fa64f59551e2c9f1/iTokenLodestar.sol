// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface iTokenLodestar {
    /**
     * @dev Calculates the exchange rate without accruing interest.
     */
    function exchangeRateStored() external view returns (uint256);
}

