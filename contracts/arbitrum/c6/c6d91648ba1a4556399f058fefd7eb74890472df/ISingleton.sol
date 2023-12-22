// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./IGuard.sol";

/**
 * @title ISingleton
 * @dev Interface for a Singleton contract.
 */
interface ISingleton {
  /**
   * @dev Add a guard contract to the Singleton.
   * @param _guard The address of the guard contract to add.
   */
  function addGuard(IGuard _guard) external;

  /**
   * @dev Remove the currently assigned guard contract from the Singleton.
   */
  function removeGuard() external;

  /**
   * @dev Validate a user request by invoking the guard contract's validation function.
   * @param dest The list of destination addresses.
   * @param value The list of values associated with each destination.
   * @param func The function call data.
   * @param validation The validation data.
   * @param sender The sender address.
   */
  function guardValidate(
    address[] calldata dest,
    uint256[] calldata value,
    bytes[] calldata func,
    bytes calldata validation,
    address sender
  ) external;
}

