// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract DelegateGuard {
    // a global variable used to determine whether it is a delegatecall
    address private immutable self = address(this);

    modifier isDelegateCall() {
        require(self != address(this), "DelegateGuard: delegate call");
        _;
    }
}

