// SPDX-License-Identifier: MIT

/***
 *      ______             _______   __
 *     /      \           |       \ |  \
 *    |  $$$$$$\ __    __ | $$$$$$$\| $$  ______    _______  ______ ____    ______
 *    | $$$\| $$|  \  /  \| $$__/ $$| $$ |      \  /       \|      \    \  |      \
 *    | $$$$\ $$ \$$\/  $$| $$    $$| $$  \$$$$$$\|  $$$$$$$| $$$$$$\$$$$\  \$$$$$$\
 *    | $$\$$\$$  >$$  $$ | $$$$$$$ | $$ /      $$ \$$    \ | $$ | $$ | $$ /      $$
 *    | $$_\$$$$ /  $$$$\ | $$      | $$|  $$$$$$$ _\$$$$$$\| $$ | $$ | $$|  $$$$$$$
 *     \$$  \$$$|  $$ \$$\| $$      | $$ \$$    $$|       $$| $$ | $$ | $$ \$$    $$
 *      \$$$$$$  \$$   \$$ \$$       \$$  \$$$$$$$ \$$$$$$$  \$$  \$$  \$$  \$$$$$$$
 *
 *
 *
 */

pragma solidity >=0.8.0;

struct DepositInfo {
    uint256 amount; // How many deposit tokens the user has provided.
    uint256 blockAmount; // Virtual amount takes in account block bonus.
    uint256 timedAmount; // Virtual amount takes in account timed bonus.
    uint256 claimedReward; // Claimed reward amount.
    uint256 cumulativeRewardPerShare; // cumulativeRewardPerShare during deposit or claim
    uint64 firstWithdrawBlockNumber; // The first block number for withdraw
}

struct BasePayload {
    // ERC20 deposit token
    address depositToken;
    // Reward start block number
    uint64 fromBlock;
    // ERC20 token to pay for staking
    address rewardToken;
    // Reward end block number
    uint64 toBlock;
    // an owner address
    address owner;
}

struct InitializePayload {
    // ERC20 deposit token
    address depositToken;
    // Reward start block number
    uint64 fromBlock;
    // ERC20 token to pay for staking
    address rewardToken;
    // Reward end block number
    uint64 toBlock;
    // Bonus block number
    uint64 bonusBlockNumber;
    // Block bonus amount in percent
    uint16 blockBonus;
    // The minimal number of block to be mined for withdraw
    uint64 minimalWithdrawBlocks;
    // The minimal deposit value
    uint256 minimalDepositAmount;
    // The numbers of blocks for time lock
    uint32[] timedBlocks;
    // The bonus percents
    uint16[] timedBonuses;
    // an owner address
    address owner;
}

