//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IRandomizer {
    function request(uint256 callbackGasLimit) external returns (uint256);

    function request(uint256 callbackGasLimit, uint256 confirmations) external returns (uint256);

    function estimateFee(uint256 callbackGasLimit) external view returns (uint256);

    function estimateFee(uint256 callbackGasLimit, uint256 confirmations) external view returns (uint256);

    function clientDeposit(address _client) external payable;

    function getFeeStats(uint256 requestId) external view returns (uint256[2] memory);

    function clientWithdrawTo(address _to, uint256 _amount) external;

    function clientBalanceOf(address _client) external view returns (uint256 deposit, uint256 reserved);
}

