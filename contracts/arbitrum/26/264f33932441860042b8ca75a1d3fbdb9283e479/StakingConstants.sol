// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20Extended, IWETH} from "./Interfaces.sol";
import "./IERC20.sol";

abstract contract StakingConstants {
    uint256 public constant BASE = 1e18;
    IWETH internal constant WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    struct StakeInfo {
        uint256 lodeAmount;
        uint256 esLODEAmount;
        uint256 lodeUnlockTime;
        uint256 lodeLockPeriod;
        uint256 lastClaimTime;
        uint256 esLODELastClaimTime;
        uint256 esLODELastConversionTime;
        uint256 relockCount;
        uint256 stakeMultiplier;
        uint256 relockMultiplier;
        uint256 claimableRewards;
        uint256 claimableUpdateTimestamp;
    }

    IERC20 public stakingToken;
    IERC20 public stakingTokenESLODE;
    IERC20 public rewardToken;
    uint256 public weeklyRewards;
    uint256 public totalStaked;
    uint256 public totalThreeMonthStaked;
    uint256 public totalSixMonthStaked;
    uint256 public totalESLODEStaked;
    uint256 public threeMonthLockBonus;
    uint256 public sixMonthLockBonus;
    uint256 public threeMonthRelockBonus;
    uint256 public sixMonthRelockBonus;
    uint256 public lastUpdateTimestamp;

    address public ROUTER;
    bool public locksCleared;

    mapping(address => StakeInfo) public stakes;

    event Staked(address indexed staker, uint256 amount, uint256 lockTime);
    event StakedESLODE(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount);
    event UnstakedESLODE(address indexed staker, uint256 amount);
    event RewardsClaimed(address indexed staker, uint256 amount);
    event ESLODEConverted(address indexed staker, uint256 amount);
    event Relocked(address indexed staker, uint256 lockTime);
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    event WeeklyRewardsUpdated(uint256 oldRewards, uint256 newRewards);
    event LocksCleared(bool locksCleared, uint256 timestamp);
    event ThreeMonthMultiplierUpdated(uint256 oldThreeMonthBonus, uint256 newThreeMonthBonus);
    event SixMonthMultiplierUpdated(uint256 oldSixMonthBonus, uint256 newSixMonthBonus);
    event ThreeMonthRelockMultiplierUpdated(uint256 oldThreeMonthRelockBonus, uint256 newThreeMonthRelockBonus);
    event SixMonthRelockMultiplierUpdated(uint256 oldSixMonthRelockBonus, uint256 newSixMonthRelockBonus);
    event RecoveredAccidentalTokens(address token, address receiver, uint256 balance);

    mapping(address => bool) public IsLocked;
}

