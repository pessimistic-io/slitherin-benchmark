//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

contract ToInitialize {
    error AlreadyInitialized();
    error NotInitialized();

    bool internal initialized;

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
            revert AlreadyInitialized();
        }
        _;
    }
}

