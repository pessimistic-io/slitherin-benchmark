// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

struct User {
    uint256 totalPegPerMember;
    uint256 pegClaimed;
    bool exist;
}

struct Stake {
    uint256 amount; ///@dev amount of peg staked.
    int256 rewardDebt; ///@dev outstanding rewards that will not be included in the next rewards calculation.
}

struct StakeClass {
    uint256 id;
    uint256 minDuration;
    uint256 maxDuration;
    bool isActive;
}

struct Lock {
    uint256 pegLocked;
    uint256 wethLocked;
    uint256 totalLpShare;
    int256 rewardDebt;
    uint48 lockedAt; // locked
    uint48 lastLockedAt; // last time user increased their lock allocation
    uint48 unlockTimestamp; // unlockable
}

struct EsPegLock {
    uint256 esPegLocked;
    uint256 wethLocked;
    uint256 totalLpShare;
    int256 rewardDebt;
    uint48 lockedAt; // locked
    uint48 unlockTimestamp; // unlockable
}

struct FeeDistributorInfo {
    uint256 accumulatedUsdcPerContract; ///@dev usdc allocated to the three contracts in the fee distributor.
    uint256 lastBalance; ///@dev last balance of usdc in the fee distributor.
    uint256 currentBalance; ///@dev current balance of usdc in the fee distributor.
    int256 stakingContractDebt; ///@dev outstanding rewards of this contract (staking) that will not be included in the next rewards calculation.
    int256 lockContractDebt; ///@dev outstanding rewards of this contract (lock) that will not be included in the next rewards calculation.
    int256 plsAccumationContractDebt; ///@dev outstanding rewards of this contract (pls accumulator) that will not be included in the next rewards calculation.
    uint48 lastUpdateTimestamp; ///@dev last time the fee distributor rewards were updated.
}

struct StakeDetails {
    int256 rewardDebt;
    uint112 plsStaked;
    uint32 epoch;
    address user;
}

struct StakedDetails {
    uint112 amount;
    uint32 lastCheckpoint;
}

struct EsPegStake {
    address user; //user who staked
    uint256 amount; //amount of esPeg staked
    uint256 amountClaimable; //amount of peg claimable
    uint256 amountClaimed; //amount of peg claimed
    uint256 pegPerSecond; //reward rate
    uint48 startTime; //time when the stake started
    uint48 fullVestingTime; //time when the stake is fully vested
    uint48 lastClaimTime; //time when the user last claimed
}

struct EsPegVest {
    address user; //user who staked
    uint256 amount; //amount of esPeg staked
    uint256 amountClaimable; //amount of peg claimable
    uint256 amountClaimed; //amount of peg claimed
    uint256 pegPerSecond; //reward rate
    uint48 startTime; //time when the stake started
    uint48 fullVestingTime; //time when the stake is fully vested
    uint48 lastClaimTime; //time when the user last claimed
}

struct Referrers {
    uint256 epochId;
    address[] referrers;
    uint256[] allocations;
}

struct Group {
    uint256 totalUsdcDistributed;
    uint256 accumulatedUsdcPerContract;
    uint256 pendingGroupUsdc;
    uint256 lastGroupBalance;
    int256 shareDebt;
    string name;
    uint16 feeShare;
    uint8 groupId; //1: staking , 2:locking , 3:plsAccumulator
}

struct Contract {
    uint256 totalUsdcReceived;
    int256 contractShareDebt;
    address contractAddress;
    uint16 feeShare;
    uint8 groupId; ///@dev group contract belongs to
}

struct GroupUpdate {
    uint8 groupId;
    uint16 newShare;
}

struct ContractUpdate {
    address contractAddress;
    uint16 newShare;
}

///@notice PepeBet structs
struct BetDetails {
    uint256 amount;
    uint256 wagerAmount;
    uint256 openingPrice;
    uint256 closingPrice;
    uint256 startTime;
    uint256 endTime;
    uint256 betId;
    address initiator;
    address betToken;
    address asset;
    bool isLong;
    bool active;
}

struct WagerTokenDetails {
    address token;
    uint256 minBetAmount;
    uint256 maxBetAmount;
}

///@notice PepeLockExtention structs
struct LockExtension {
    address user;
    uint256 amount;
    uint48 lockDuration;
}

///@notice PepeDegen struct
struct DegenEpoch {
    uint32 epochId;
    address[] users;
    uint256[] amounts;
}

