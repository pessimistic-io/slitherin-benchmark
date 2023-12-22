// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IPriceOracleManager {
    event NewWrapperRegistered(address indexed _underlying, address indexed _wrapperAddress);

    event WrapperUpdated(address indexed _underlying, address indexed _wrapperAddress);

    function setWrapper(address _underlying, address _wrapperAddress) external;

    function updateWrapper(address _underlying, address _wrapperAddress) external;

    function getExternalPrice(
        address _underlying,
        bytes calldata _data
    ) external returns (uint256 price, uint8 decimals, bool success);
}

