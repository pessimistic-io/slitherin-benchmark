// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./BoringOwnable.sol";

contract FooBar is BoringOwnable {
    uint256 foo;
    uint256 foo2;

    constructor(uint256 _foo, uint256 _foo2) {
        foo = _foo;
        foo2 = _foo2;
    }
}

