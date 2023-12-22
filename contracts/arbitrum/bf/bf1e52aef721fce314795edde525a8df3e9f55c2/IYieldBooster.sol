// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
interface IYieldBooster {
  function allocate(uint256 _amount) external;
  function deallocate(uint256 _amount) external;
  function getMultiplier(
    uint256 _stakedAmount,
    uint256 _totalStaked,
    uint256 _boostedPointsAmount,
    uint256 _totalBoostedPoints,
    uint256 _maxMultiplier
  ) external view returns (uint256);
}

