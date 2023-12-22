// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./Ownable2StepUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

contract StakingRewards is Ownable2StepUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct StakeInfo {
        uint256 lodeAmount;
        uint256 esLODEAmount;
        uint256 lodeLockTime;
        uint256 lastClaimTime;
        uint256 esLODELastClaimTime;
        uint256 esLODELastConversionTime;
        uint256 relockCount;
    }

    IERC20 public stakingToken;
    IERC20 public stakingTokenESLODE;
    IERC20 public rewardToken;
    uint256 public weeklyRewards;
    uint256 public totalStaked;
    uint256 public totalESLODEStaked;
    address public ROUTER;

    mapping(address => StakeInfo) public stakes;

    event Staked(address indexed staker, uint256 amount, uint256 lockTime);
    event StakedESLODE(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount);
    event UnstakedESLODE(address indexed staker, uint256 amount);
    event RewardsClaimed(address indexed staker, uint256 amount);
    event ESLODEConverted(address indexed staker, uint256 amount);
    event Relocked(address indexed staker, uint256 lockTime);
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);

    function initialize(
        address _stakingToken,
        address _stakingTokenESLODE,
        address _rewardToken,
        address _router
    ) external initializer {
        stakingToken = IERC20(_stakingToken);
        stakingTokenESLODE = IERC20(_stakingTokenESLODE);
        rewardToken = IERC20(_rewardToken);
        ROUTER = _router;

        __Ownable2Step_init();
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    function updateWeeklyRewards(uint256 newRewards) external {
        require(msg.sender == ROUTER, "StakingRewards: Update Rewards Unauthorized");
        weeklyRewards = newRewards;
    }

    function stake(uint256 amount, uint256 lockTime) external whenNotPaused nonReentrant {
        require(lockTime == 0 || lockTime == 90 days || lockTime == 180 days, "Invalid lock time");

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        if (lockTime == 0) {
            _stakeInternal(msg.sender, amount, 0);
        } else {
            _stakeInternal(msg.sender, amount, lockTime);
        }

        emit Staked(msg.sender, amount, lockTime);
    }

    function stakeESLODE(uint256 amount) external whenNotPaused nonReentrant {
        StakeInfo storage stakeInfoESLODEStake = stakes[msg.sender];

        stakingTokenESLODE.safeTransferFrom(msg.sender, address(this), amount);

        stakeInfoESLODEStake.esLODEAmount += amount;

        totalESLODEStaked += amount;

        emit StakedESLODE(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        StakeInfo storage stakeInfo = stakes[msg.sender];

        require(stakeInfo.lodeAmount >= amount, "Not enough staked LODE");

        if (stakeInfo.lodeLockTime != 0 && block.timestamp < stakeInfo.lodeLockTime) {
            // LODE is still locked, revert the unstake
            revert("LODE still locked");
        }

        _unstake(msg.sender, amount);
    }

    function unstakeESLODE(uint256 amount) external nonReentrant {
        StakeInfo storage stakeInfoESLODEUnstake = stakes[msg.sender];

        require(stakeInfoESLODEUnstake.esLODEAmount >= amount, "Not enough staked esLODE");

        _unstakeESLODE(msg.sender, amount);
    }

    function claimRewards() public nonReentrant {
        StakeInfo storage stakeInfoClaim = stakes[msg.sender];

        uint256 pendingRewards = calculateReward(msg.sender);

        stakeInfoClaim.lastClaimTime = block.timestamp;
        stakeInfoClaim.esLODELastClaimTime = block.timestamp;

        rewardToken.safeTransfer(msg.sender, pendingRewards);

        if (stakeInfoClaim.esLODEAmount > 0) {
            _convertESLODE(msg.sender);
        }

        emit RewardsClaimed(msg.sender, pendingRewards);
    }

    function getAccountTotalSharePercentage(address account) external view returns (uint256 totalSharePercentage) {
        StakeInfo storage stakeInfo = stakes[account];

        uint256 lodeAdjustedAmount = stakeInfo.lodeAmount * _getTotalMultiplier(account);
        uint256 totalAdjustedStaked = totalStaked + totalESLODEStaked;
        uint256 combinedAmount = lodeAdjustedAmount + stakeInfo.esLODEAmount;

        if (totalAdjustedStaked > 0) {
            totalSharePercentage = (combinedAmount * 1e18) / totalAdjustedStaked;
        } else {
            totalSharePercentage = 0;
        }
    }

    function relock() external nonReentrant whenNotPaused {
        StakeInfo storage stakeInfoRelock = stakes[msg.sender];

        require(stakeInfoRelock.lodeLockTime != 0, "No existing lock time");

        uint256 lockTime = stakeInfoRelock.lodeLockTime;
        uint256 relockPeriod = lockTime == 90 days ? 90 days : 180 days;

        uint256 newLockTime = lockTime + relockPeriod;

        stakeInfoRelock.lodeLockTime = newLockTime;
        stakeInfoRelock.relockCount += 1;

        emit Relocked(msg.sender, newLockTime);
    }

    function calculateReward(address staker) public view returns (uint256) {
        StakeInfo storage stakeInfoCalc = stakes[staker];

        uint256 rewardMultiplier = _getTotalMultiplier(staker);
        uint256 timeSinceLastClaimLODE = block.timestamp - stakeInfoCalc.lastClaimTime;
        uint256 timeSinceLastClaimESLODE = block.timestamp - stakeInfoCalc.esLODELastClaimTime;
        uint256 lodeReward;
        uint256 esLODEReward;

        if (stakeInfoCalc.lodeAmount != 0) {
            lodeReward =
                (stakeInfoCalc.lodeAmount * weeklyRewards * timeSinceLastClaimLODE * rewardMultiplier) /
                (totalStaked * 7 days);
        }

        if (stakeInfoCalc.esLODEAmount != 0) {
            esLODEReward =
                (stakeInfoCalc.esLODEAmount * weeklyRewards * timeSinceLastClaimESLODE * rewardMultiplier) /
                (totalESLODEStaked * 7 days);
        }

        return lodeReward + esLODEReward;
    }

    function _stakeInternal(address staker, uint256 amount, uint256 lockTime) internal {
        StakeInfo storage stakeInfoStake = stakes[staker];

        stakingToken.safeTransferFrom(staker, address(this), amount);

        stakeInfoStake.lodeAmount += amount;

        if (lockTime != 0) {
            stakeInfoStake.lodeLockTime = block.timestamp + lockTime;
        }

        totalStaked += amount;

        emit Staked(staker, amount, lockTime);
    }

    function _unstake(address staker, uint256 amount) internal {
        StakeInfo storage stakeInfoUnstake = stakes[staker];

        require(stakeInfoUnstake.lodeAmount >= amount, "Not enough staked LODE");

        if (stakeInfoUnstake.lodeLockTime != 0 && block.timestamp < stakeInfoUnstake.lodeLockTime) {
            // LODE is still locked, revert the unstake
            revert("LODE still locked");
        }

        stakeInfoUnstake.lodeAmount -= amount;
        totalStaked -= amount;

        stakingToken.safeTransfer(staker, amount);

        emit Unstaked(staker, amount);
    }

    function _unstakeESLODE(address staker, uint256 amount) internal {
        StakeInfo storage stakeInfoESLODEUnstake = stakes[staker];

        require(stakeInfoESLODEUnstake.esLODEAmount >= amount, "Not enough staked esLODE");

        claimRewards();

        stakeInfoESLODEUnstake.esLODEAmount -= amount;
        totalESLODEStaked -= amount;

        stakingTokenESLODE.safeTransfer(staker, amount);

        emit UnstakedESLODE(staker, amount);
    }

    function _getLockMultiplier(uint256 lockPeriod, uint256 relockCount) internal pure returns (uint256) {
        if (lockPeriod == 0) {
            return 10;
        } else if (lockPeriod == 90 days) {
            return 14 + (relockCount * 5);
        } else if (lockPeriod == 180 days) {
            return 20 + (relockCount * 10);
        }
        return 10;
    }

    function _getTotalMultiplier(address staker) internal view returns (uint256) {
        StakeInfo storage stakeInfoGetMult = stakes[staker];
        uint256 lockMultiplier = _getLockMultiplier(stakeInfoGetMult.lodeLockTime, stakeInfoGetMult.relockCount);
        return lockMultiplier;
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

            emit ESLODEConverted(staker, amountToConvert);
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

