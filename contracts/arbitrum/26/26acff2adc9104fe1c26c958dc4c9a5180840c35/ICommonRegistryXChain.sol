// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICommonRegistryXChain {
    function contracts(bytes32 _hash) external view returns(address);
    function clearAddress(string calldata _name) external;
    function setAddress(string calldata _name, address _addr) external;
    function getAddr(string calldata _name) external view returns(address);
    function getAddrIfNotZero(string calldata _name) external view returns(address);
    function getAddrIfNotZero(bytes32 _hash) external view returns(address);
}
