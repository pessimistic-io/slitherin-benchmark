// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IYieldHandler {
    function deposit(address _from, uint256 _amount) external;
    function withdraw(address _from, uint256 _amount) external;
    function getBalance(address _address) external returns(uint256);
}
