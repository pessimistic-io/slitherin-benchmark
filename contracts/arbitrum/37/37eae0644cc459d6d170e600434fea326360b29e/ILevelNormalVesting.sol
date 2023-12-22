// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ILevelNormalVesting {
    function getReservedAmount(address _user) external view returns (uint256);
}

