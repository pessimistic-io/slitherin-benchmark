// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IxTIG is IERC20 {
    function vestingPeriod() external view returns (uint256);
    function earlyUnlockPenalty() external view returns (uint256);
    function epochFeesGenerated(uint256 _epoch) external view returns (uint256);
    function epochAllocation(uint256 _epoch) external view returns (uint256);
    function epochAllocationClaimed(uint256 _epoch) external view returns (uint256);
    function feesGenerated(uint256 _epoch, address _trader) external view returns (uint256);
    function tigAssetValue(address _tigAsset) external view returns (uint256);
    function createVest() external;
    function claimTig() external;
    function earlyClaimTig() external;
    function claimFees() external;
    function addFees(address _trader, address _tigAsset, uint256 _fees) external;
    function addTigRewards(uint256 _epoch, uint256 _amount) external;
    function setTigAssetValue(address _tigAsset, uint256 _value) external;
    function setTrading(address _address) external;
    function setExtraRewards(address _address) external;
    function setVestingPeriod(uint256 _time) external;
    function setEarlyUnlockPenalty(uint256 _percent) external;
    function whitelistReward(address _rewardToken) external;
    function recoverTig(uint256 _amount) external;
    function contractPending(address _token) external view returns (uint256);
    function extraRewardsPending(address _token) external view returns (uint256);
    function pending(address _user, address _token) external view returns (uint256);
    function pendingTig(address _user) external view returns (uint256);
    function pendingEarlyTig(address _user) external view returns (uint256);
    function upcomingXTig(address _user) external view returns (uint256);
    function stakedTigBalance() external view returns (uint256);
    function userRewardBatches(address _user) external view returns (RewardBatch[] memory);
    function unclaimedAllocation(uint256 _epoch) external view returns (uint256);
    function currentEpoch() external view returns (uint256);

    struct RewardBatch {
        uint256 amount;
        uint256 unlockTime;
    }

    event TigRewardsAdded(address indexed sender, uint256 amount);
    event TigVested(address indexed account, uint256 amount);
    event TigClaimed(address indexed user, uint256 amount);
    event EarlyTigClaimed(address indexed user, uint256 amount, uint256 penalty);
    event TokenWhitelisted(address token);
    event TokenUnwhitelisted(address token);
    event RewardClaimed(address indexed user, uint256 reward);
    event VestingPeriodUpdated(uint256 time);
    event EarlyUnlockPenaltyUpdated(uint256 percent);
    event TradingUpdated(address indexed trading);
    event SetExtraRewards(address indexed extraRewards);
    event FeesAdded(address indexed _trader, address indexed _tigAsset, uint256 _amount, uint256 indexed _value);
}

