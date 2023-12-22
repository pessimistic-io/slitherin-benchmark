// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Strings} from "./Strings.sol";

import {WithPausable, LibPausable} from "./LibPausable.sol";
import {PausableStorage} from "./PausableStorage.sol";
import {WithRoles} from "./LibAccessControl.sol";
import {DEFAULT_ADMIN_ROLE} from "./AccessControlStorage.sol";

contract PausableFacet is WithPausable, WithRoles {
  using Strings for uint256;
  using LibPausable for PausableStorage;

  /**
   * @dev Triggers stopped state.
   *
   * Requirements:
   *
   * - The contract must not be paused.
   */
  function pause() external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
    PausableStorage storage pauseStorage = LibPausable.DS();
    pauseStorage.pause();
  }

  /**
   * @dev Returns to normal state.
   *
   * Requirements:
   *
   * - The contract must be paused.
   */
  function unpause() external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
    PausableStorage storage pauseStorage = LibPausable.DS();
    pauseStorage.unpause();
  }

  /**
   * @dev Returns true if the contract is paused, and false otherwise.
   */
  function isPaused() external view returns (bool) {
    PausableStorage storage pauseStorage = LibPausable.DS();
    return pauseStorage.paused;
  }

  /**
   * @dev Returns the timestamp when the contract was paused.
   */
  function pausedAt() external view returns (uint256) {
    PausableStorage storage pauseStorage = LibPausable.DS();
    if (pauseStorage.pausedAt == 0) revert LibPausable.NotPausedError();
    return pauseStorage.pausedAt;
  }
}

