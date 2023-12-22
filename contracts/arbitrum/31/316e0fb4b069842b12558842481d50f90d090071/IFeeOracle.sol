// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

interface IFeeOracle {
  function getFee(
    address account,
    uint256 value
  ) external view returns (uint256);
}

