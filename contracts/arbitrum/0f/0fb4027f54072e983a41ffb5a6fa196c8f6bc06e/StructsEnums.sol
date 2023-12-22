//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

struct DevelopmentGround {
    address owner;
    uint64 lockPeriod;
    uint64 amountPosition;
    uint64 entryTime;
    uint64 lastRewardTime;
    uint256 bonesStaked;
    uint256 currentPitsLockPeriod;
    Grounds ground;
}

struct LaborGround {
    address owner;
    uint32 lockTime;
    uint32 supplyId;
    uint32 animalId;
    uint256 requestId;
    Jobs job;
}

struct Cave {
    address owner;
    uint48 stakingTime;
    uint48 lastRewardTimestamp;
}

struct CavesFeInfo {
    uint256 reward;
    uint128 stakedSmols;
    uint128 timeLeft;
}

struct DevGroundFeInfo {
    uint96 timeLeft;
    uint96 daysStaked;
    uint64 stakedSmols;
    uint256 skillLevel;
    uint256 bonesAccured;
    uint256 totalBonesStaked;
    Grounds ground;
}

struct BonesFeInfo {
    uint256 balance;
    uint256 timeStaked;
}

struct LaborGroundFeInfo {
    uint64 timeLeft;
    uint64 tokenId;
    uint64 animalId;
    uint64 supplyId;
}

/**
 * token id
 * bones occured
 * primary skill level
 * days left
 */

enum Jobs {
    Digging,
    Foraging,
    Mining
}

enum Grounds {
    Chambers,
    Garden,
    Battlefield
}

