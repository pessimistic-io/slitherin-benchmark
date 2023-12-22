// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;


interface IFundManagerFactory {
    function getProtocolLibForType(uint256) external view returns (address);

    function owner() external view returns (address);

    function isSigner(address) external view returns (bool);

    function isGelatoFeeCollector(address) external view returns (bool);

    function addStrategy() external;

    function removeStrategy() external;
}

