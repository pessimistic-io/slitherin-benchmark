// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./IERC20.sol";

interface IRewarder {
    function onReward(uint256 pid, address user, address recipient, uint256 onyxAmount, uint256 newTokenAmount) external;
    function pendingTokens(uint256 pid, address user, uint256 onyxAmount) external view returns (IERC20[] memory, uint256[] memory);
}
