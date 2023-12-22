// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";

import {IRouter} from "./IRouter.sol";

interface IFarm {
    function rewardToken() external view returns (IERC20);

    function balance() external view returns (uint256);

    function stake(uint256 _amount) external;

    function unstake(uint256 _amount, address _receiver) external;

    function earned() external view returns (uint256);

    function pendingRewards() external view returns (address[] memory, uint256[] memory);

    function pendingRewardsToLP() external view returns (uint256);

    function claim(address _receiver) external;

    function claimAndStake(IRouter router) external returns (uint256);

    function exit() external;
}

