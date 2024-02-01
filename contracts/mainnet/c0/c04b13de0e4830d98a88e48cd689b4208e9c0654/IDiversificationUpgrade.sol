// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IDiversificationUpgrade {
  function lockWithVestingTo(
    address beneficiary,
    uint256 amount,
    uint256 timestamp
  ) external;
}

