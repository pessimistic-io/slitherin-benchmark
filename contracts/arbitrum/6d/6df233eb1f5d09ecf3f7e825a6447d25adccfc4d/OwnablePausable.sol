// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./Ownable.sol";
import "./Pausable.sol";

import "./IOwnablePausableEvents.sol";

contract OwnablePausable is Ownable, Pausable, IOwnablePausableEvents {
    function toggle() external {
        _checkOwner();
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
        emit PauseStateSet(paused());
    }

    function _requireNotPaused() internal view virtual override {
        require(!paused(), "Contract Paused");
    }
}

