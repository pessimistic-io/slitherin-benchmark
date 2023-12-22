// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.18;

import {IERC20Extended, IWETH, IVotingPower} from "./Interfaces.sol";
import "./IERC20Upgradeable.sol";
import "./IERC20.sol";

abstract contract StakingConstants {
    struct EsLODEStake {
        uint256 baseAmount;
        uint256 amount;
        uint256 startTimestamp;
        uint256 alreadyConverted;
    }

    struct StakingInfo {
        uint256 lodeAmount;
        uint256 stLODEAmount;
        uint256 startTime;
        uint256 lockTime;
        uint256 relockStLODEAmount;
        uint256 nextStakeId;
        uint256 totalEsLODEStakedByUser;
        uint256 threeMonthRelockCount;
        uint256 sixMonthRelockCount;
    }

    mapping(address => EsLODEStake[]) public esLODEStakes;

    mapping(address => StakingInfo) public stakers;

    IERC20Upgradeable public LODE;
    IERC20Upgradeable public WETH;
    IERC20Upgradeable public esLODE;

    uint256 public weeklyRewards;
    uint256 public lastUpdateTimestamp;

    uint256 public totalStaked;
    uint256 public totalEsLODEStaked;
    uint256 public totalRelockStLODE;

    uint256 public stLODE3M;
    uint256 public stLODE6M;
    uint256 public relockStLODE3M;
    uint256 public relockStLODE6M;

    address public routerContract;
    IVotingPower public votingContract;

    uint256 public constant BASE = 1e18;
    uint256 public constant MUL_CONSTANT = 1e14;

    bool public withdrawEsLODEAllowed;
    bool public locksLifted;

    struct UserInfo {
        uint96 amount; // Staking tokens the user has provided
        int128 wethRewardsDebt;
    }

    uint256 public wethPerSecond;
    uint128 public accWethPerShare;
    uint96 public shares; // total staked,TODO:WAS PRIVATE PRIOR TO TESTING
    uint32 public lastRewardSecond;

    mapping(address => UserInfo) public userInfo;

    error DEPOSIT_ERROR();
    error WITHDRAW_ERROR();
    error UNAUTHORIZED();

    event StakedLODE(address indexed user, uint256 amount, uint256 lockTime);
    event StakedEsLODE(address indexed user, uint256 amount);
    event UnstakedLODE(address indexed user, uint256 amount);
    event UnstakedEsLODE(address indexed user, uint256 amount);
    event esLODEConverted(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 reward);
    event StakingLockedCanceled();
    event WeeklyRewardsUpdated(uint256 newRewards);
    event StakingRatesUpdated(uint256 stLODE3M, uint256 stLODE6M, uint256 vstLODE3M, uint256 vstLODE6M);
    event StakingPaused();
    event StakingUnpaused();
    event RouterContractUpdated(address newRouterContract);
    event VotingContractUpdated(address newVotingContract);
    event esLODEUnlocked(bool state, uint256 timestamp);
    event Relocked(address user, uint256 lockTime);
    event EmergencyWithdrawal(uint256 amount);
    event LocksLifted(bool state, uint256 timestamp);
}

//following initial deployment begin new storage contracts below starting with V1

