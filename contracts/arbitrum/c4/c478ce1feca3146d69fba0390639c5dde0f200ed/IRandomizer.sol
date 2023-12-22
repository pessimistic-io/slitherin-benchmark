// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IRandomizer {
    function request(uint256 callbackGasLimit) external returns (uint256);

    function request(uint256 callbackGasLimit, uint256 confirmations) external returns (uint256);

    function clientWithdrawTo(address _to, uint256 _amount) external;

    function estimateFee(uint256 _gas) external view returns (uint256);

    function estimateFeeUsingGasPrice(uint256 _callbackGasLimit, uint256 _gasPrice) external view returns (uint256);

    function clientBalanceOf(address _clientAddress) external view returns (uint256);
}

