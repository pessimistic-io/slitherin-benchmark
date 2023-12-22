// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;


interface IDeFiBridgeState {
  struct Chain {
    bool defined;
    bool enabled;
    address pool;
    bytes32 sender;
    address defi;
  }
}
