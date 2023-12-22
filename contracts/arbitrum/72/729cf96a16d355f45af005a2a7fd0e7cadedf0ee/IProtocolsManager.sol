// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.8.15;


interface IProtocolsManager {

    function  query(string memory protocolName) external view returns (address contractAddress, bool allowTrading);
    function  isCurrencySupported(string memory protocolName, address token) external view returns(bool);
}


