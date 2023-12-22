// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;
import "./IRewardsPool.sol";

interface ILootBoxRevealer {
  function reveal(
    uint256[] calldata _lootBoxTokenIds,
    uint256[] calldata _lootBoxAmount
  ) external;

  //=======================================
  // Events
  //=======================================
  event LootBoxRevealedEvent(
    uint256 revealIndex,
    address lootboxOwner,
    uint256 lootboxTokenId,
    uint256[] rewardTokenTypes,
    address[] rewardTokenAddresses,
    uint256[] rewardTokenIds,
    uint256[] rewardAmounts
  );
}

