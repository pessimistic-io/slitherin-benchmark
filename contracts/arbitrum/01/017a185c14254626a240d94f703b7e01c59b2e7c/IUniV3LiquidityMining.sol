//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

interface IUniV3LiquidityMining {
  function upKeep(uint64 maxIndex, bool rolloverRewards) external;

  function incentives(uint256 activeIncentiveId)
    external
    view
    returns (
      uint256 totalRewardUnclaimed,
      uint160 totalSecondsClaimedX128,
      uint96 numberOfStakes,
      uint64 startTime,
      uint64 endTime
    );

  function scheduleIncentive(uint256 rewards, uint64 startTime, uint64 endTime)
    external;

  function activeIncentiveId() external view returns (uint256);

  function keeper() external view returns (address);

  function setKeeper(address newKeeper) external;

  function upKeepCursor() external view returns (uint64);
}

