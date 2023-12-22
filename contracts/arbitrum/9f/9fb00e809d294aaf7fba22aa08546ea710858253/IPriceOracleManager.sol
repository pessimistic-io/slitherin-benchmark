// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IPriceOracleManager {
    function getPriceInUSD(address sourceToken) external returns (uint256);
}

