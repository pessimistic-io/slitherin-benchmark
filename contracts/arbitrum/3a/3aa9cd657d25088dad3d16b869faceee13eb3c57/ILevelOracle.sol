// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILevelOracle {
  function getPrice(address _token, bool _max) external view returns (uint256);
}

