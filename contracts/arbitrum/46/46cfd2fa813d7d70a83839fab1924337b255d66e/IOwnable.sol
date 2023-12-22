// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IOwnable {

  // stateful functions
  function transferOwnership(address newOwner) external;
}

