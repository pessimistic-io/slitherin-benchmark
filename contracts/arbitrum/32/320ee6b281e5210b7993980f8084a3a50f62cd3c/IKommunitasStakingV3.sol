// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IKommunitasStakingV3 {
  function giveawayStakedAmount() external view returns(uint256);
  function getUserStakedGiveawayEligibleBeforeDate(
    address _staker,
    uint128 _beforeAt
  ) external view returns (uint256 lockedTokens);
}
