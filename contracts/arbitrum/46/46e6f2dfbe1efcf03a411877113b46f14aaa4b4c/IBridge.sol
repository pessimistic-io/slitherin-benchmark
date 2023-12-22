// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IBridge {
  function deposit(uint8, bytes32, bytes memory, bytes memory) external payable;
}

