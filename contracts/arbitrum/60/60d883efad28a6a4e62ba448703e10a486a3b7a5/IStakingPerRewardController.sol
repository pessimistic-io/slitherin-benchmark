// SPDX-License-Identifier: MIT

import { IERC20 } from "./IERC20.sol";
import { ISnapshottable } from "./ISnapshottable.sol";

pragma solidity ^0.8.0;

/**
 * @title IStakingPerRewardController
 * @dev Minimal interface for staking that RewardController requires
 */
interface IStakingPerRewardController {
    function getStakersCount() external view returns (uint256);
    function getStakers(uint256 idx) external view returns (address);
    function stakeFor(address _account, uint256 _amount) external;
}
