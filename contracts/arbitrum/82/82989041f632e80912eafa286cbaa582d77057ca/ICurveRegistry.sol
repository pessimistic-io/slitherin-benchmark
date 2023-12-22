// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

interface ICurveRegistry {
  function find_pool_for_coins(
    address _from,
    address _to,
    uint256 i
  ) external view returns (address);

  function get_coin_indices(
    address pool,
    address _from,
    address _to
  ) external view returns (int128, int128, bool);
}

