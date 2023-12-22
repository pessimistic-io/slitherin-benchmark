// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IAccessControl.sol";

interface IUserAccess is IAccessControl {
  function setRoleAdmin(bytes32 role, bytes32 adminRole) external;
}
