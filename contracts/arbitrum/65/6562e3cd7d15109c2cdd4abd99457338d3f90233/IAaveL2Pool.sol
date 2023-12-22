
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IAaveL2Pool {
  function supplyWithPermit(bytes32 args, bytes32 r, bytes32 s) external;
  function supply(bytes32 arg) external;
  function borrow(bytes32 args) external;
  function repay(bytes32 args) external returns (uint256);
  function withdraw(bytes32 args) external;
}

