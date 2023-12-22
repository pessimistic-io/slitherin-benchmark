// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IPriceOracle {
    error NotTrustedAddress();
    error ZeroAddress();
    error InvalidDecimals();
    error notContract();

    event PriceUpdated(address indexed _oracleAddress, uint256 _newPrice, uint256 _timestamp);
    event NodeRegistered(address indexed _oracleAddress, address indexed _nodeAddress);
    event NodeUnRegistered(address indexed _oracleAddress, address indexed _nodeAddress);

    function getLatestPrice(
        bytes calldata _flag
    ) external view returns (uint256 _currentPrice, uint256 _lastPrice, uint256 _lastUpdateTimestamp, uint8 _decimals);
}

