// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TokenVault_Types.sol";

struct VaultInfo {
  uint start; // start of tokenIds
  uint size; // size of collection in case of overflow
  uint deposits; // number of deposits
  uint depositSpots; // max number of deposits
}

struct PlayerToken {
  UserToken token;
  bool active;
}
