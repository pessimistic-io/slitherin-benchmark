// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./UserOperation.sol";

/**
 * @dev Interface for a Guard contract.
 */
interface IGuard {
  /**
   * @dev Emitted when the Singleton contract address is changed.
   * @param singleton The new Singleton contract address.
   */
  event SingletonChanged(address indexed singleton);

  /**
   * @dev Validates a user request by checking the signature and others parameters.
   * @param dest The list of destination addresses.
   * @param value The list of values associated with each destination.
   * @param func The function call data.
   * @param sender The sender address.
   * @param validation The validation data.
   * @notice This function should implement checks for signature validation, valid timestamp,
   *         authorized signer, and valid target addresses.
   */
  function validateRequest(
    address[] calldata dest,
    uint256[] calldata value,
    bytes[] calldata func,
    address sender,
    bytes calldata validation
  ) external;

  /**
   * @dev Changes the Singleton contract address, callable only by the owner.
   * @param newSingleton The new Singleton contract address.
   */
  function changeSingleton(address newSingleton) external;
}

