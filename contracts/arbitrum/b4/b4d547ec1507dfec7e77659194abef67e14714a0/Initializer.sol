// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

abstract contract Initializer {
  bool public initialized = false;

  modifier isUninitialized() {
    require(!initialized, "Initializer: initialized");
    _;
    initialized = true;
  }

  modifier isInitialized() {
    require(initialized, "Initializer: uninitialized");
    _;
  }
}

