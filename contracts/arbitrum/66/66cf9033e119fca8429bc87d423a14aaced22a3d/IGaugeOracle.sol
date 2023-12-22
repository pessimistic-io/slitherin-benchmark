// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IGaugeOracle {
  function getRate(
    uint256,
    uint256,
    address
  ) external view returns (uint256);
}

