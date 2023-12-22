// SPDX-License-Identifier: MIT

import { IERC20 } from "./IERC20.sol";
import { IStakingPerRewardController } from "./IStakingPerRewardController.sol";
import { IStakingPerTierController } from "./IStakingPerTierController.sol";

pragma solidity ^0.8.0;

/**
 * @title IStakingPerLegacyTierReward
 * @dev Minimal interface for staking that the legacy RewardController and TierController requires
 */
interface IStakingPerLegacyTierReward is IStakingPerRewardController, IStakingPerTierController {
}
