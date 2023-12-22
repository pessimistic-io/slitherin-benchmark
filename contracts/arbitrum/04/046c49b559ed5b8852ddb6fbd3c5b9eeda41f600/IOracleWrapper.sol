// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IOracleWrapper {
    struct OracleResponse {
        uint8 decimals;
        uint256 currentPrice;
        uint256 lastPrice;
        uint256 lastUpdateTimestamp;
        bool success;
    }

    error TokenIsNotRegistered(address _underlying);
    error ResponseFromOracleIsInvalid(address _token, address _oracle);
    error ZeroAddress();
    error NotContract(address _address);
    error InvalidDecimals();

    event NewOracle(address indexed _aggregatorAddress, address _underlying);

    function getExternalPrice(
        address _underlying,
        bytes calldata _flag
    ) external view returns (uint256 price, uint8 decimals, bool success);
}

