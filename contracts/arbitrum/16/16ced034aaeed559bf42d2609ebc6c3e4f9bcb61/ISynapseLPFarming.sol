//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.7;

interface ISynapseLPFarming {
    function deposit(uint256 pid, uint256 amount, address to) external;
    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external;
    function harvest(uint256 pid, address to) external;
    function userInfo(uint256, address) external view returns (uint256 amount);
}

