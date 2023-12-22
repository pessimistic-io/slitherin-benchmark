// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IPoolConfigProvider {
  // Returns the numerator in the dynamic rate formula.
  //
  function getN(uint64 _poolId) external view returns (uint256);
}

