// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./ActionInfo.sol";

interface IActionManager {
  /// @dev Associate a new address with an actionId
  function setActionAddress(uint16 actionId, address actionAddress) external; // onlyOwner

  /// @dev Retrieve the address associated with an actionId
  function getActionAddress(uint16 actionId) external view returns (address);

  /// @dev getActionCount getActionInfoAt together allow enumeration of all actions
  function getActionCount() external view returns (uint256);

  function getActionInfoAt(uint256 index) external view returns (ActionInfo memory);
}

