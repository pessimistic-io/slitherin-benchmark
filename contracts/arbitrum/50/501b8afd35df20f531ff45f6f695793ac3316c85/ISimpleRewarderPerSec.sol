// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IERC20} from "./IERC20.sol";

import {IAPTFarm} from "./IAPTFarm.sol";
import {IRewarder} from "./IRewarder.sol";
import {IWrappedNative} from "./IWrappedNative.sol";

interface ISimpleRewarderPerSec is IRewarder {
    error SimpleRewarderPerSec__OnlyAPTFarm();
    error SimpleRewarderPerSec__InvalidTokenPerSec();

    event OnReward(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    /**
     * @notice Info of each APTFarm user.
     * `amount` LP token amount the user has provided.
     * `rewardDebt` The amount of YOUR_TOKEN entitled to the user.
     */
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 unpaidRewards;
    }

    /**
     * @notice Info of each APTFarm farmInfo.
     * `accTokenPerShare` Amount of YOUR_TOKEN each LP token is worth.
     * `lastRewardTimestamp` The last timestamp YOUR_TOKEN was rewarded to the farmInfo.
     */
    struct FarmInfo {
        uint256 accTokenPerShare;
        uint256 lastRewardTimestamp;
    }

    function apToken() external view returns (IERC20);

    function aptFarm() external view returns (IAPTFarm);

    function wNative() external view returns (IWrappedNative);

    function isNative() external view returns (bool);

    function tokenPerSec() external view returns (uint256);

    function initialize(uint256 tokenPerSec, address owner) external;
}

