// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface ISolidlyGauge {
    function balanceOf(address account) external view returns (uint);
    function claimFees() external returns (uint claimed0, uint claimed1);
    function deposit(uint amount, uint tokenId) external;
    function depositAll(uint tokenId) external;
    function earned(address token, address account) external view returns (uint);
    function getReward(address account, address[] memory tokens) external;
    function withdraw(uint amount) external;
    function withdrawAll() external;
    function withdrawAllAndHarvest(uint amount) external;
}
