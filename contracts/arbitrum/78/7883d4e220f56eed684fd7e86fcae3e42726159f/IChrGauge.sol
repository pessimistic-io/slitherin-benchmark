// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IGauge {
    
    function deposit(uint256 amount) external;

    function withdrawAndHarvest(uint256 tokenId) external;

    function getAllReward() external;

    function balanceOf(address account) external view returns (uint256);
}

