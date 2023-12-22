// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./Context.sol";

abstract contract Stoppable is Context {

    /**
     * @dev Emitted when the stop is triggered by `account`.
     */
    event Stopped(address account);

    /**
     * @dev Emitted when the stop is lifted by `account`.
     */
    event Resumed(address account);

    bool private _stopped;

    /**
     * @dev Initializes the contract in unstopped state.
     */
    constructor() {
        _stopped = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not stopped.
     *
     * Requirements:
     *
     * - The contract must not be stopped.
     */
    modifier whenNotStopped() {
        _requireNotStopped();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is stopped.
     *
     * Requirements:
     *
     * - The contract must be stopped.
     */
    modifier whenStopped() {
        _requireStopped();
        _;
    }

    /**
     * @dev Returns true if the contract is stopped, and false otherwise.
     */
    function stopped() public view virtual returns (bool) {
        return _stopped;
    }

    /**
     * @dev Throws if the contract is stopped.
     */
    function _requireNotStopped() internal view virtual {
        require(!stopped(), "Stoppable: stopped");
    }

    /**
     * @dev Throws if the contract is not stopped.
     */
    function _requireStopped() internal view virtual {
        require(stopped(), "Stoppable: not stopped");
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be stopped.
     */
    function _stop() internal virtual whenNotStopped {
        _stopped = true;
        emit Stopped(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be stopped.
     */
    function _resume() internal virtual whenStopped {
        _stopped = false;
        emit Resumed(_msgSender());
    }
}

