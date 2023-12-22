// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./IERC20Metadata.sol";

interface IXARXStaker {
    function deposit(uint256 amount) external returns (bool);

    function withdraw(uint256 amount) external returns (bool);

    function emergencyWithdraw() external returns (bool);

    function pendingRewards(
        address account
    ) external view returns (IERC20Metadata[] memory tokens, uint256[] memory rewardAmounts);
}

