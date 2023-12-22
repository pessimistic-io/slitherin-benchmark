// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

//=======================================
// Enums
//=======================================

enum RewardTokenType {
  ERC20,
  ERC721,
  ERC1155
}

//=======================================
// Structs
//=======================================
struct DispensedRewards {
  uint256 nextRandomBase;
  DispensedReward[] rewards;
}

struct DispensedReward {
  RewardTokenType tokenType;
  address token;
  uint256 tokenId;
  uint256 amount;
}

//=========================================================================================================================================
// Rewards will use 10^3 decimal point to calculate drop rates. This means if something has a drop rate of 100% it's represented as 100000
//=========================================================================================================================================
uint256 constant DECIMAL_POINT = 1000;
uint256 constant ONE_HUNDRED = 100 * DECIMAL_POINT;

//=======================================================================================================================================================
// Dispenser contract for rewards. Each RewardPool is divided into subpools (in case of lootboxes: for different rarities, or realm specific pools, etc).
//=======================================================================================================================================================
interface IRewardsPool {
  //==============================================================================================================================
  // Dispenses random rewards from the pool
  //==============================================================================================================================
  function dispenseRewards(
    uint64 subPoolId,
    uint256 randomNumberBase,
    address receiver
  ) external returns (DispensedRewards memory);
}

