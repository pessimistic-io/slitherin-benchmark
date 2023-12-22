// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ICERC20, SushiRouterInterface, PriceOracleProxyETHInterface, IERC20Extended, IGLPRouter, IPlutusDepositor, IWETH, ICETH} from "./Interfaces.sol";
import "./ISwapRouter.sol";
import "./AggregatorV3Interface.sol";
import "./IERC20.sol";

contract StakingConstants {
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
}

