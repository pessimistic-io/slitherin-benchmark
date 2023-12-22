// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {IERC20} from "./IERC20.sol";

import {ITimeswapV2Behavior} from "./ITimeswapV2Behavior.sol";

interface ITimeswapV2LevelBehavior is ITimeswapV2Behavior {
  function farmingMaster() external view returns (address);

  function rewardToken() external view returns (IERC20);

  function pid() external view returns (uint256);

  function lpToken() external view returns (address);

  function pendingReward(address token, uint256 strike, uint256 maturity) external view returns (uint256);

  function mint(address to, uint256 amount) external;

  function burn(address to, uint256 amount) external;

  // function harvest(address token, uint256 strike, uint256 maturity, address to) external returns (uint256 amount);
}

