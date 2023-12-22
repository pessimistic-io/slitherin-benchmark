// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;
pragma abicoder v2;

interface ICurvePool {
  function get_dy(
    int128 i,
    int128 j,
    uint256 _dx
  ) external view returns (uint256);

  function exchange(
    int128 i,
    int128 j,
    uint256 _dx,
    uint256 _min_dy
  ) external payable returns (uint256);
}

