// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {PausableStorage} from "./PausableStorage.sol";

import {PonzuStorage} from "./PonzuStorage.sol";
import {LibPonzu} from "./LibPonzu.sol";

abstract contract WithPausable {
  /**
   * @dev Modifier to make a function callable only when the contract is not paused.
   *
   * Requirements:
   *
   * - The contract must not be paused.
   */
  modifier whenNotPaused() {
    PausableStorage storage pauseStorage = LibPausable.DS();
    if (pauseStorage.paused) revert LibPausable.PausedError();
    _;
  }

  /**
   * @dev Modifier to make a function callable only when the contract is paused.
   *
   * Requirements:
   *
   * - The contract must be paused.
   */
  modifier whenPaused() {
    PausableStorage memory pauseStorage = LibPausable.DS();
    if (!pauseStorage.paused) revert LibPausable.NotPausedError();
    _;
  }
}

library LibPausable {
  using LibPausable for PausableStorage;
  using LibPonzu for PonzuStorage;

  bytes32 internal constant DIAMOND_STORAGE_POSITION =
    keccak256("diamond.standard.pausable.storage");

  error PausedError();
  error NotPausedError();

  /**
   * @dev Emitted when the pause is triggered by `account`.
   */
  event Paused(address account);

  /**
   * @dev Emitted when the pause is lifted by `account`.
   */
  event Unpaused(address account);

  function DS() internal pure returns (PausableStorage storage ds) {
    bytes32 position = DIAMOND_STORAGE_POSITION;
    assembly {
      ds.slot := position
    }
  }

  /**
   * @dev Triggers stopped state.
   *
   * Requirements:
   *
   * - The contract must not be paused.
   */
  function pause(PausableStorage storage pauseStorage) internal {
    pauseStorage.paused = true;
    pauseStorage.pausedAt = uint64(block.timestamp);
    emit Paused(msg.sender);
  }

  /**
   * @dev Returns to normal state.
   *
   * Requirements:
   *
   * - The contract must be paused.
   */
  function unpause(PausableStorage storage pauseStorage) internal {
    pauseStorage.paused = false;
    PonzuStorage storage ponzuStorage = LibPonzu.DS();
    ponzuStorage.addPausedTime(uint64(block.timestamp) - pauseStorage.pausedAt);

    pauseStorage.pausedAt = 0;
    emit Unpaused(msg.sender);
  }
}

