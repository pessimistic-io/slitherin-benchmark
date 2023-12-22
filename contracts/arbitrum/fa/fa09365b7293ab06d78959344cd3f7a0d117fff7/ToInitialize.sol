//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

contract ToInitialize {
    error AlreadtInitialized();
    error NotInitialized();

    bool public initialized = false;

    modifier isInitialized() {
        _isInitialized();
        _;
    }

    function _isInitialized() internal view {
        if (!initialized) {
            revert NotInitialized();
        }
    }

    modifier notInitialized() {
        if (initialized) {
            revert AlreadtInitialized();
        }
        _;
    }
}

