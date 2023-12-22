// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITokenVesting {
  function IS_CONSENSUS_VESTING() external view returns (bool);
  function teamWallet() external view returns (address);
  function marketingWallet() external view returns (address);
  function emitToken() external;
}

