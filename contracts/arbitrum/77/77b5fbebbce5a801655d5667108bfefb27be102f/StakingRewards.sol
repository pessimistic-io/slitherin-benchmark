// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

contract StakingRewards is OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct StakeInfo {
        uint256 lodeAmount;
        uint256 vLODEAmount;
        uint256 lodeLockTime;
        uint256 lastClaimTime;
        uint256 vLODELastClaimTime;
        uint256 vLODELastConversionTime;
        uint256 relockCount;
    }

    IERC20 public stakingToken;
    IERC20 public stakingTokenVLODE;
    IERC20 public rewardToken;
    uint256 public weeklyRewards;
    uint256 public totalStaked;
    uint256 public totalVLODEStaked;
    address public ROUTER;

    mapping(address => StakeInfo) public stakes;

    event Staked(address indexed staker, uint256 amount, uint256 lockTime);
    event StakedVLODE(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount);
    event UnstakedVLODE(address indexed staker, uint256 amount);
    event RewardsClaimed(address indexed staker, uint256 amount);
    event VLODEConverted(address indexed staker, uint256 amount);
    event Relocked(address indexed staker, uint256 lockTime);
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);

    function initialize(
        address _stakingToken,
        address _stakingTokenVLODE,
        address _rewardToken,
        address _router
    ) external initializer {
        stakingToken = IERC20(_stakingToken);
        stakingTokenVLODE = IERC20(_stakingTokenVLODE);
        rewardToken = IERC20(_rewardToken);
        ROUTER = _router;

        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    function updateWeeklyRewards(uint256 newRewards) external {
        require(msg.sender == ROUTER, "StakingRewards: Update Rewards Unauthorized");
        weeklyRewards = newRewards;
    }

    function stake(uint256 amount, uint256 lockTime) external whenNotPaused nonReentrant {
        require(lockTime == 0 || lockTime == 90 days || lockTime == 180 days, "Invalid lock time");

        StakeInfo storage stakeInfoStake = stakes[msg.sender];

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        stakeInfoStake.lodeAmount += amount;
        stakeInfoStake.lodeLockTime = lockTime;
        stakeInfoStake.lastClaimTime = block.timestamp;

        totalStaked += amount;

        emit Staked(msg.sender, amount, lockTime);
    }

    function stakeVLODE(uint256 amount) external whenNotPaused nonReentrant {
        StakeInfo storage stakeInfoVLODEStake = stakes[msg.sender];

        stakingTokenVLODE.safeTransferFrom(msg.sender, address(this), amount);

        stakeInfoVLODEStake.vLODEAmount += amount;
        stakeInfoVLODEStake.vLODELastClaimTime = block.timestamp;
        stakeInfoVLODEStake.vLODELastConversionTime = block.timestamp;

        totalVLODEStaked += amount;

        emit StakedVLODE(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        StakeInfo storage stakeInfoUnstake = stakes[msg.sender];

        require(stakeInfoUnstake.lodeAmount >= amount, "Not enough staked LODE");
        require(block.timestamp >= stakeInfoUnstake.lodeLockTime, "LODE still locked");

        stakeInfoUnstake.lodeAmount -= amount;
        totalStaked -= amount;

        stakingToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    function unstakeVLODE(uint256 amount) external nonReentrant {
        StakeInfo storage stakeInfoVLODEUnstake = stakes[msg.sender];

        require(stakeInfoVLODEUnstake.vLODEAmount >= amount, "Not enough staked vLODE");

        stakeInfoVLODEUnstake.vLODEAmount -= amount;
        totalVLODEStaked -= amount;

        stakingTokenVLODE.safeTransfer(msg.sender, amount);

        emit UnstakedVLODE(msg.sender, amount);
    }

    function claimRewards() external nonReentrant {
        StakeInfo storage stakeInfoClaim = stakes[msg.sender];

        uint256 pendingRewards = _calculateReward(msg.sender);

        stakeInfoClaim.lastClaimTime = block.timestamp;
        stakeInfoClaim.vLODELastClaimTime = block.timestamp;

        rewardToken.safeTransfer(msg.sender, pendingRewards);

        if (stakeInfoClaim.vLODEAmount > 0) {
            _convertVLODE(msg.sender);
        }

        emit RewardsClaimed(msg.sender, pendingRewards);
    }

    function getAccountTotalSharePercentage(address account) external view returns (uint256 totalSharePercentage) {
        StakeInfo storage stakeInfo = stakes[account];

        uint256 lodeAdjustedAmount = stakeInfo.lodeAmount * _getTotalMultiplier(account);
        uint256 totalAdjustedStaked = totalStaked + totalVLODEStaked;
        uint256 combinedAmount = lodeAdjustedAmount + stakeInfo.vLODEAmount;

        if (totalAdjustedStaked > 0) {
            totalSharePercentage = (combinedAmount * 1e18) / totalAdjustedStaked;
        } else {
            totalSharePercentage = 0;
        }
    }

    function relock(uint256 lockTime) external nonReentrant whenNotPaused {
        require(lockTime == 90 days || lockTime == 180 days, "Invalid lock time");

        StakeInfo storage stakeInfoRelock = stakes[msg.sender];

        require(stakeInfoRelock.lodeLockTime == 0, "Already locked");

        stakeInfoRelock.lodeLockTime = lockTime;
        stakeInfoRelock.relockCount += 1;

        emit Relocked(msg.sender, lockTime);
    }

    function _calculateReward(address staker) internal view returns (uint256) {
        StakeInfo storage stakeInfoCalc = stakes[staker];

        uint256 rewardMultiplier = _getTotalMultiplier(staker);
        uint256 timeSinceLastClaimLODE = block.timestamp - stakeInfoCalc.lastClaimTime;
        uint256 timeSinceLastClaimVLODE = block.timestamp - stakeInfoCalc.vLODELastClaimTime;

        uint256 lodeReward = (stakeInfoCalc.lodeAmount * weeklyRewards * timeSinceLastClaimLODE * rewardMultiplier) /
            (totalStaked * 7 days);
        uint256 vLODEReward = (stakeInfoCalc.vLODEAmount * weeklyRewards * timeSinceLastClaimVLODE) /
            (totalVLODEStaked * 7 days);

        return lodeReward + vLODEReward;
    }

    function _getLockMultiplier(uint256 lockPeriod, uint256 relockCount) public pure returns (uint256) {
        if (lockPeriod == 0) {
            return 10;
        } else if (lockPeriod == 90 days) {
            return 14 + (relockCount * 5);
        } else if (lockPeriod == 180 days) {
            return 20 + (relockCount * 10);
        }
        return 10;
    }

    function _getTotalMultiplier(address staker) public view returns (uint256) {
        StakeInfo storage stakeInfoGetMult = stakes[staker];
        uint256 lockMultiplier = _getLockMultiplier(stakeInfoGetMult.lodeLockTime, stakeInfoGetMult.relockCount);
        return lockMultiplier;
    }

    function _convertVLODE(address staker) internal {
        StakeInfo storage stakeInfoConvert = stakes[staker];

        uint256 timeSinceLastConversion = block.timestamp - stakeInfoConvert.vLODELastConversionTime;
        uint256 amountToConvert = (stakeInfoConvert.vLODEAmount * timeSinceLastConversion) / (365 days);

        if (amountToConvert > 0) {
            stakeInfoConvert.vLODEAmount -= amountToConvert;
            stakeInfoConvert.lodeAmount += amountToConvert;
            stakeInfoConvert.vLODELastConversionTime = block.timestamp;

            stakingTokenVLODE.safeTransfer(address(this), amountToConvert);
            stakingToken.safeTransfer(staker, amountToConvert);

            emit VLODEConverted(staker, amountToConvert);
        }
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function _setRouter(address newRouter) external onlyOwner {
        address oldRouter = ROUTER;
        ROUTER = newRouter;
        emit RouterUpdated(oldRouter, ROUTER);
    }
}

