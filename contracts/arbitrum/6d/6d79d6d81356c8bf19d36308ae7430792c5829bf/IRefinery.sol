// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRefinery {
    function refinateFromRewards(uint256 _amount, address _user) external;
    function instantRefinate(uint256 _amount) external;
}

