// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ISimpleAccountFactory {
    function getAddress(address owner,uint256 salt) external view returns (address);
}
