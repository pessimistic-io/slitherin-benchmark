// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IVodkaVault {

    function totalSupply() external view returns (uint256);

    function getAggregatePosition(address user) external view returns (uint256);

    function handleAndCompoundRewards() external;
}
