// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

abstract contract Pausable {
    bool private _paused;

    function paused() public view returns (bool) {
        return _paused;
    }

    function _requireNotPaused() internal view {
        if (_paused) {
            revert PauseError();
        }
    }

    function _togglePause() internal whenNotPaused {
        _paused = !_paused;
        emit PauseChanged(msg.sender, _paused);
    }

    modifier whenPaused() {
        if (!_paused) {
            revert PauseError();
        }
        _;
    }

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    event PauseChanged(address _account, bool _paused);

    error PauseError();
}

