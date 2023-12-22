// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPoolLens {
  function getTrancheValue(
    address _tranche,
    bool _max
  ) external view returns (uint256);

  function getPoolValue(bool _max) external view returns (uint256);

  function getAssetAum(
    address _tranche,
    address _token,
    bool _max
  ) external view returns (uint256);

  function getAssetPoolAum(
    address _token,
    bool _max
  ) external view returns (uint256);
}

