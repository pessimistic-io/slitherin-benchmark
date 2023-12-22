// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRewarderMiniChefV2 {
    function SUSHI() external view returns (address);
    function lpToken(uint256) external view returns (address);
    function pendingSushi(uint256, address) external view returns (uint256);
    function userInfo(uint256, address) external view returns (uint256, int256);
    function deposit(uint256, uint256, address) external;
    function withdraw(uint256, uint256, address) external;
    function harvest(uint256, address) external;
}

