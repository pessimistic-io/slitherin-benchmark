// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface ILevelHelper {
    function getUserLevel(address _account) external returns (uint256);

    function getTraderLevel(address _account) external returns (uint256);

    function getRefLevel(address _account) external returns (uint256);
}

