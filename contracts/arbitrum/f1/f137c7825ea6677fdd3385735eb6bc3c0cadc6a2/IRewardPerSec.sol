// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;
import { IERC20 } from "./IERC20.sol";

interface IRewardPerSec {
    function onesVKAReward(address user, uint256 newLpAmount) external;

    function pendingTokens(address user) external view returns (uint256 pending);

    function rewardToken() external view returns (IERC20);
}

