// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

abstract contract PausableWithoutContext {
    bool private _paused;

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!_paused, "Paused");
        _;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function _pause(bool _p) internal virtual {
        _paused = _p;
    }
}

