// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Pausable.sol";

abstract contract PausableTimed is Pausable {

    uint256 public lastPauseTime;

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual override whenNotPaused {
        lastPauseTime = block.timestamp;
        super._pause();
    }

}

