// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Interfaces.sol";
import "./WETHUtils.sol";

import "./StakingConstants.sol";

contract StakingRewards is
    StakingConstants,
    Ownable2StepUpgradeable,
    WETHUtils,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    function initialize(
        address _stakingToken,
        address _stakingTokenESLODE,
        address _rewardToken,
        address _router,
        uint256 _threeMonthLockBonus,
        uint256 _sixMonthLockBonus,
        uint256 _threeMonthRelockBonus,
        uint256 _sixMonthRelockBonus
    ) external initializer {
        stakingToken = IERC20(_stakingToken);
        stakingTokenESLODE = IERC20(_stakingTokenESLODE);
        rewardToken = IERC20(_rewardToken);
        ROUTER = _router;
        threeMonthLockBonus = _threeMonthLockBonus;
        sixMonthLockBonus = _sixMonthLockBonus;
        threeMonthRelockBonus = _threeMonthRelockBonus;
        sixMonthRelockBonus = _sixMonthRelockBonus;

        WETH.approve(address(this), type(uint256).max);

        __Ownable2Step_init();
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    function updateWeeklyRewards(uint256 newRewards) external {
        require(msg.sender == ROUTER, "StakingRewards: Update Rewards Unauthorized");
        uint256 oldRewards = weeklyRewards;
        weeklyRewards = newRewards;
        lastUpdateTimestamp = block.timestamp;
        emit WeeklyRewardsUpdated(oldRewards, newRewards);
    }

    function stake(uint256 amount, uint256 lockTime) external whenNotPaused nonReentrant {
        require(lockTime == 0 || lockTime == 90 days || lockTime == 180 days, "Invalid lock time");
        require(amount != 0, "Invalid LODE stake amount");

        _stakeInternal(amount, lockTime);

        emit Staked(msg.sender, amount, lockTime);
    }

    function stakeESLODE(uint256 amount) external whenNotPaused nonReentrant {
        require(amount != 0, "Invalid esLODE stake amount");

        _stakeESLODEInternal(amount);

        emit StakedESLODE(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        StakeInfo storage stakeInfo = stakes[msg.sender];

        require(stakeInfo.lodeAmount >= amount, "Not enough staked LODE");
        require(amount < totalStaked, "Insufficient tokens to unstake");

        if (locksCleared == true) {
            _unstake(msg.sender, amount);
        } else if (stakeInfo.lodeLockPeriod != 0 && block.timestamp < stakeInfo.lodeUnlockTime) {
            // LODE is still locked, revert the unstake
            revert("LODE still locked");
        } else if (stakeInfo.lodeLockPeriod == 0) {
            _unstake(msg.sender, amount);
        }
    }

    function unstakeESLODE(uint256 amount) external nonReentrant {
        StakeInfo storage stakeInfoESLODEUnstake = stakes[msg.sender];

        require(stakeInfoESLODEUnstake.esLODEAmount >= amount, "Not enough staked esLODE");
        require(amount < totalESLODEStaked, "Insufficient tokens to unstake");

        claimRewards();

        _unstakeESLODE(msg.sender, amount);
    }

    function claimRewards() public nonReentrant {
        StakeInfo storage stakeInfoClaim = stakes[msg.sender];

        uint256 pendingRewards = calculateReward(msg.sender);

        stakeInfoClaim.lastClaimTime = block.timestamp;
        stakeInfoClaim.esLODELastClaimTime = block.timestamp;
        stakeInfoClaim.claimableRewards -= pendingRewards;

        WETH.withdraw(pendingRewards);

        (bool sent, ) = msg.sender.call{value: pendingRewards}("");
        require(sent, "Failed to send Ether");

        if (stakeInfoClaim.esLODEAmount > 0) {
            _convertESLODE(msg.sender);
        }

        emit RewardsClaimed(msg.sender, pendingRewards);
    }

    function getAccountTotalSharePercentage(address account) external view returns (uint256 totalSharePercentage) {
        StakeInfo storage stakeInfo = stakes[account];

        uint256 lodeAdjustedAmount = stakeInfo.lodeAmount * getTotalMultiplier(account);
        uint256 totalAdjustedStaked = totalStaked + totalESLODEStaked;
        uint256 combinedAmount = lodeAdjustedAmount + stakeInfo.esLODEAmount;

        if (totalAdjustedStaked > 0) {
            totalSharePercentage = (combinedAmount * 1e18) / totalAdjustedStaked;
        } else {
            totalSharePercentage = 0;
        }
    }

    function getTotalMultiplier(address staker) public view returns (uint256) {
        StakeInfo storage stakeInfoGetMult = stakes[staker];
        uint256 lockMultiplier = getLockMultiplier(stakeInfoGetMult.lodeUnlockTime, stakeInfoGetMult.relockCount);
        return lockMultiplier;
    }

    function relock(uint256 lockTime) external nonReentrant whenNotPaused {
        require(lockTime == 0 || lockTime == 90 days || lockTime == 180 days, "Invalid lock time");
        StakeInfo storage stakeInfoRelock = stakes[msg.sender];

        require(stakeInfoRelock.lodeAmount != 0, "No staked position");
        require(stakeInfoRelock.lodeLockPeriod != 0, "No locked position");
        require(block.timestamp > stakeInfoRelock.lodeUnlockTime, "Not eligible to be relocked yet");

        uint256 bonusMultiplier;

        if (lockTime == 90 days) {
            bonusMultiplier = threeMonthRelockBonus;
        } else if (lockTime == 180 days) {
            bonusMultiplier = sixMonthRelockBonus;
        }

        stakeInfoRelock.relockMultiplier += bonusMultiplier;

        uint256 newLockTime = stakeInfoRelock.lodeUnlockTime + lockTime;

        stakeInfoRelock.lodeUnlockTime = newLockTime;
        stakeInfoRelock.relockCount += 1;

        emit Relocked(msg.sender, newLockTime);
    }

    function calculateReward(address staker) public returns (uint256) {
        StakeInfo storage stakeInfoCalc = stakes[staker];
        uint256 totalAdjustedStake = calculateTotalAdjustedStake();
        uint256 stakeMultiplier = stakeInfoCalc.stakeMultiplier;
        uint256 relockMultiplier = stakeInfoCalc.relockMultiplier;
        uint256 totalMultiplier;
        if (relockMultiplier == 0) {
            totalMultiplier = stakeMultiplier;
        } else {
            totalMultiplier = stakeMultiplier + relockMultiplier;
        }
        uint256 totalMultiplierMantissa = BASE + (totalMultiplier * 1e16);
        uint256 timeSinceLastClaimLODE;
        uint256 timeSinceLastClaimESLODE;
        if (stakeInfoCalc.lastClaimTime == 0 || stakeInfoCalc.lastClaimTime < lastUpdateTimestamp) {
            timeSinceLastClaimLODE = lastUpdateTimestamp;
        } else {
            timeSinceLastClaimLODE = block.timestamp - stakeInfoCalc.lastClaimTime;
        }
        if (stakeInfoCalc.esLODELastClaimTime == 0 || stakeInfoCalc.esLODELastClaimTime < lastUpdateTimestamp) {
            timeSinceLastClaimESLODE = lastUpdateTimestamp;
        } else {
            timeSinceLastClaimESLODE = block.timestamp - stakeInfoCalc.esLODELastClaimTime;
        }
        uint256 lodeReward;
        uint256 esLODEReward;

        if (totalStaked > 0) {
            uint256 lodeShare = (stakeInfoCalc.lodeAmount * totalMultiplierMantissa * BASE) / totalAdjustedStake;
            //uint256 maxWeeklyReward = (weeklyRewards * lodeShare) / BASE;
            lodeReward = (weeklyRewards * lodeShare * timeSinceLastClaimLODE) / (7 days * BASE);
            updateClaimableRewards(msg.sender, lodeReward);
        } else {
            lodeReward = 0;
        }

        if (totalESLODEStaked > 0) {
            uint256 esLODEShare = (stakeInfoCalc.esLODEAmount * BASE) / totalESLODEStaked;
            esLODEReward = (weeklyRewards * esLODEShare * timeSinceLastClaimESLODE) / (7 days * BASE);
            updateClaimableRewards(msg.sender, esLODEReward);
        } else {
            esLODEReward = 0;
        }

        return lodeReward + esLODEReward;
    }

    function calculateTotalAdjustedStake() public view returns (uint256) {
        uint256 threeMonthLockMantissa = BASE + (threeMonthLockBonus * 1e16);
        uint256 sixMonthLockMantissa = BASE + (sixMonthLockBonus * 1e16);
        uint256 remainingStaked = totalStaked - totalThreeMonthStaked - totalSixMonthStaked;
        uint256 totalAdjustedStake = (((totalThreeMonthStaked * threeMonthLockMantissa) / BASE) +
            ((totalSixMonthStaked * sixMonthLockMantissa) / BASE) +
            remainingStaked);
        return totalAdjustedStake;
    }

    function updateClaimableRewards(address staker, uint256 amount) internal {
        StakeInfo storage stakeInfo = stakes[staker];
        if (stakeInfo.claimableUpdateTimestamp < lastUpdateTimestamp) {
            stakeInfo.claimableRewards += amount;
            stakeInfo.claimableUpdateTimestamp = block.timestamp;
        } else {
            return;
        }
    }

    function getTotalStakedLODE() public view returns (uint256) {
        return totalStaked;
    }

    function getTotalStakedESLODE() public view returns (uint256) {
        return totalESLODEStaked;
    }

    function getLockMultiplier(uint256 lockPeriod, uint256 relockCount) internal pure returns (uint256) {
        if (lockPeriod == 0) {
            return 10;
        } else if (lockPeriod == 90 days) {
            return 14 + (relockCount * 5);
        } else if (lockPeriod == 180 days) {
            return 20 + (relockCount * 10);
        }
        return 10;
    }

    function _stakeInternal(uint256 amount, uint256 lockTime) internal {
        StakeInfo storage stakeInfoInternalStake = stakes[msg.sender];
        bool isLocked = IsLocked[msg.sender];

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        if (lockTime == 0 && isLocked == false) {
            stakeInfoInternalStake.lodeAmount += amount;
        } else if (lockTime == 90 days && isLocked == false) {
            stakeInfoInternalStake.lodeAmount += amount;
            stakeInfoInternalStake.lodeUnlockTime = block.timestamp + lockTime;
            stakeInfoInternalStake.lodeLockPeriod = lockTime;
            stakeInfoInternalStake.stakeMultiplier = threeMonthLockBonus;
            totalThreeMonthStaked += amount;
            IsLocked[msg.sender] = true;
        } else if (lockTime == 180 days && isLocked == false) {
            stakeInfoInternalStake.lodeAmount += amount;
            stakeInfoInternalStake.lodeUnlockTime = block.timestamp + lockTime;
            stakeInfoInternalStake.lodeLockPeriod = lockTime;
            stakeInfoInternalStake.stakeMultiplier = sixMonthLockBonus;
            totalSixMonthStaked += amount;
            IsLocked[msg.sender] = false;
        } else if (isLocked == true) {
            if (stakeInfoInternalStake.lodeLockPeriod != lockTime) {
                revert("Mismatched Lock Times");
            } else if (lockTime == 90 days) {
                stakeInfoInternalStake.lodeAmount += amount;
                totalThreeMonthStaked += amount;
            } else if (lockTime == 180 days) {
                stakeInfoInternalStake.lodeAmount += amount;
                totalSixMonthStaked += amount;
            }
        }
        totalStaked += amount;
    }

    function _stakeESLODEInternal(uint256 amount) internal {
        StakeInfo storage stakeInfoESLODEStake = stakes[msg.sender];

        if (stakeInfoESLODEStake.esLODELastConversionTime == 0) {
            stakeInfoESLODEStake.esLODELastConversionTime = block.timestamp;
        }

        stakingTokenESLODE.safeTransferFrom(msg.sender, address(this), amount);

        stakeInfoESLODEStake.esLODEAmount += amount;

        totalESLODEStaked += amount;
    }

    function _unstake(address staker, uint256 amount) internal {
        StakeInfo storage stakeInfoInternalUnstake = stakes[staker];

        stakeInfoInternalUnstake.lodeAmount -= amount;

        totalStaked -= amount;

        uint256 lockPeriod = stakeInfoInternalUnstake.lodeLockPeriod;

        if (lockPeriod == 90 days) {
            totalThreeMonthStaked -= amount;
        } else if (lockPeriod == 180 days) {
            totalSixMonthStaked -= amount;
        }

        stakeInfoInternalUnstake.stakeMultiplier = 0;

        stakingToken.safeTransfer(staker, amount);

        emit Unstaked(staker, amount);
    }

    function _unstakeESLODE(address staker, uint256 amount) internal {
        StakeInfo storage stakeInfoInternalUnstakeESLODE = stakes[staker];

        stakeInfoInternalUnstakeESLODE.esLODEAmount -= amount;

        totalESLODEStaked -= amount;

        stakingTokenESLODE.safeTransfer(staker, amount);

        emit UnstakedESLODE(staker, amount);
    }

    function _convertESLODE(address staker) internal {
        StakeInfo storage stakeInfoConvert = stakes[staker];

        uint256 timeSinceLastConversion = block.timestamp - stakeInfoConvert.esLODELastConversionTime;
        uint256 amountToConvert = (stakeInfoConvert.esLODEAmount * timeSinceLastConversion) / (365 days);

        if (amountToConvert > 0) {
            stakeInfoConvert.esLODEAmount -= amountToConvert;
            stakeInfoConvert.lodeAmount += amountToConvert;
            stakeInfoConvert.esLODELastConversionTime = block.timestamp;

            // Burn the esLODE tokens from the staker's balance within the contract
            totalESLODEStaked -= amountToConvert;
            // Add the equivalent amount to the staker's LODE balance within the contract
            totalStaked += amountToConvert;

            stakingTokenESLODE.safeTransferFrom(address(this), address(0), amountToConvert);

            emit ESLODEConverted(staker, amountToConvert);
        }
    }

    function _updateRouter(address newRouter) external onlyOwner {
        require(newRouter != address(0), "Invalid router address");

        address oldRouter = ROUTER;
        ROUTER = newRouter;

        emit RouterUpdated(oldRouter, newRouter);
    }

    function _clearLocks(bool clearLocks) external onlyOwner {
        locksCleared = clearLocks;
        emit LocksCleared(clearLocks, block.timestamp);
    }

    function _updateThreeMonthMultiplier(uint256 newThreeMonthMultiplier) external onlyOwner {
        require(newThreeMonthMultiplier != 0, "Invalid Three Month Multiplier");
        uint256 oldThreeMonthMultiplier = threeMonthRelockBonus;
        threeMonthRelockBonus = newThreeMonthMultiplier;
        emit ThreeMonthMultiplierUpdated(oldThreeMonthMultiplier, threeMonthRelockBonus);
    }

    function _updateSixMonthMultiplier(uint256 newSixMonthMultiplier) external onlyOwner {
        require(newSixMonthMultiplier != 0, "Invalid Six Month Multiplier");
        uint256 oldSixMonthMultiplier = sixMonthRelockBonus;
        sixMonthRelockBonus = newSixMonthMultiplier;
        emit SixMonthMultiplierUpdated(oldSixMonthMultiplier, sixMonthRelockBonus);
    }

    function _recoverAccidentalTokens(IERC20[] memory tokens) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            require(address(tokens[i]) != address(stakingToken), "Cannot retrieve staked tokens");
            require(address(tokens[i]) != address(stakingTokenESLODE), "Cannot retrieve staked vesting tokens");

            uint256 balance = tokens[i].balanceOf(address(this));
            require(balance > 0, "No tokens to retrieve");

            tokens[i].transfer(msg.sender, balance);
            emit RecoveredAccidentalTokens(address(tokens[i]), msg.sender, balance);
        }
    }

    function pauseStaking() external onlyOwner {
        _pause();
    }

    function unpauseStaking() external onlyOwner {
        _unpause();
    }
}

