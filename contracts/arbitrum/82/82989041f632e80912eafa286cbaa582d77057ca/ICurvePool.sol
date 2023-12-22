// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

interface ICurvePool {
  function fee() external view returns (uint256);

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

