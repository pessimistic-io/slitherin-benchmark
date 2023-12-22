// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGauge {
    function balanceOf(address user) external view returns (uint);
    function earned(address token, address user) external view returns (uint);
    function earned(address user) external view returns (uint);
    function setBalance(address user, uint256 amount) external;
    function deposit(uint256 tokenId, uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward(address account, address[] memory tokens) external;
}

