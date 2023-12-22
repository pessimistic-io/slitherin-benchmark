// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8;

interface ITokenFactory {
    function bridgeFee() external view returns (uint256);
    function feeTo() external view returns (address);
}
