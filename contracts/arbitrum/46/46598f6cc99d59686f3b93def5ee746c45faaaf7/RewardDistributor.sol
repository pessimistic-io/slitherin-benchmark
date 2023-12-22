// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IMintable.sol";
import "./Ownable.sol";
import "./Math.sol";
import "./SafeCast.sol";

contract RewardDistributor is Ownable {
    using SafeCast for uint256;

    uint64 public constant REWARD_START_TIME = 1697587200; // 2023-10-18 00:00:00 UTC
    uint64 public constant REWARD_HALVING_TIME = 1702166400; // 2023-12-10 00:00:00 UTC
    uint64 public constant REWARD_END_TIME = 1709942400; // 2024-03-09 00:00:00 UTC

    IMintable public immutable mintManager;

    uint64 public lastUpdateTime;
    uint96 public dailyReward;
    uint96 public unclaimedRewards;

    mapping(address => bool) public claimers;

    event Registered(address indexed claimer);
    event Unregistered(address indexed claimer);
    event DailyRewardSet(uint96 amount, uint64 time);
    event Claimed(address indexed claimer, uint96 amount, uint64 time);

    modifier onlyClaimer() {
        require(claimers[_msgSender()], "Invalid Claimer");
        _;
    }

    constructor(uint96 _dailyReward, IMintable _mintManager) {
        dailyReward = _dailyReward;
        mintManager = _mintManager;
        lastUpdateTime = _calculateStartOfDayTime(block.timestamp);
        unclaimedRewards = _calculateReward(REWARD_START_TIME, lastUpdateTime);
    }

    function register(address _claimer) external onlyOwner {
        require(!claimers[_claimer], "Already registered");
        claimers[_claimer] = true;
        emit Registered(_claimer);
    }

    function unregister(address _claimer) external onlyOwner {
        require(claimers[_claimer], "Already unregistered");
        delete claimers[_claimer];
        emit Unregistered(_claimer);
    }

    function setDailyReward(uint96 _amount) external onlyOwner {
        uint64 startTime = _calculateStartOfDayTime(block.timestamp);
        unclaimedRewards += _calculateReward(lastUpdateTime, startTime);
        lastUpdateTime = startTime;
        dailyReward = startTime >= REWARD_HALVING_TIME ? _amount * 2 : _amount;
        emit DailyRewardSet(_amount, lastUpdateTime);
    }

    function claim() external onlyClaimer {
        uint64 startTime = _calculateStartOfDayTime(block.timestamp);
        uint96 rewards = _calculateReward(lastUpdateTime, startTime);
        rewards += unclaimedRewards;
        lastUpdateTime = startTime;
        unclaimedRewards = 0;
        mintManager.mint(msg.sender, rewards);
        emit Claimed(msg.sender, rewards, lastUpdateTime);
    }

    function claimable() external view returns (uint96 rewards) {
        uint64 startTime = _calculateStartOfDayTime(block.timestamp);
        rewards = _calculateReward(lastUpdateTime, startTime);
        rewards += unclaimedRewards;
    }

    function _calculateReward(uint64 _rewardStartTime, uint64 _rewardEndTime) private view returns (uint96 rewards) {
        if (_rewardStartTime >= REWARD_END_TIME) {
            return 0;
        }
        if (_rewardEndTime <= REWARD_HALVING_TIME) {
            return Math.mulDiv(_rewardEndTime - _rewardStartTime, dailyReward, 1 days).toUint96();
        }
        if (_rewardStartTime >= REWARD_HALVING_TIME) {
            return
                Math
                    .mulDiv(Math.min(_rewardEndTime, REWARD_END_TIME) - _rewardStartTime, dailyReward, 1 days * 2)
                    .toUint96();
        }
        rewards = Math.mulDiv(REWARD_HALVING_TIME - _rewardStartTime, dailyReward, 1 days).toUint96();
        rewards += Math
            .mulDiv(Math.min(_rewardEndTime, REWARD_END_TIME) - REWARD_HALVING_TIME, dailyReward, 1 days * 2)
            .toUint96();
    }

    function _calculateStartOfDayTime(uint256 timestamp) private pure returns (uint64 startTime) {
        uint256 time = timestamp - (timestamp % 1 days);
        startTime = time.toUint64();
    }
}

