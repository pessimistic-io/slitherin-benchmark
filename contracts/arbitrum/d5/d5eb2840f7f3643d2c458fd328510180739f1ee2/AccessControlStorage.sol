// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct RoleData {
  mapping(address => bool) members;
  bytes32 adminRole;
  address[] membersList;
}

struct AccessControlStorage {
  mapping(bytes32 => RoleData) roles;
}

bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
bytes32 constant GAME_ADMIN_ROLE = keccak256("GAME_ADMIN_ROLE");

