// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IRandomizer {
    function request(uint256 callbackGasLimit) external returns (uint256);

    function request(uint256 callbackGasLimit, uint256 confirmations) external returns (uint256);

    function clientWithdrawTo(address _to, uint256 _amount) external;
}

