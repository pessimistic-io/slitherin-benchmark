// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {IERC20} from "./IERC20.sol";

import {ITimeswapV2Behavior} from "./ITimeswapV2Behavior.sol";
import {IStableJoeStaking} from "./IStableJoeStaking.sol";

interface ITimeswapV2StableJoeStakingBehavior is ITimeswapV2Behavior {
    function stableJoeStakingFarm() external view returns (IStableJoeStaking);

    function rewardToken() external view returns (IERC20);

    function joeToken() external view returns (IERC20);

    function pendingReward(address token, uint256 strike, uint256 maturity) external view returns (uint256);

    function mint(address to, uint256 amount) external;

    function burn(address to, uint256 amount) external;

    function harvest(address token, uint256 strike, uint256 maturity, address to) external returns (uint256 amount);

    function update(address token, uint256 strike, uint256 maturity) external;
}

