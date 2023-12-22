// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IBalanceHelper {
    function getUserBalance(address _account) external view returns (uint256);
    function getTraderBalance(address _account) external view returns (uint256);
    function getRefBalance(address _account) external view returns (uint256);
}

