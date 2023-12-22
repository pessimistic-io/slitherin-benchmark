// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { SecurityStorage } from "./SecurityStorage.sol";

abstract contract ReentrancyGuard {
    using SecurityStorage for SecurityStorage.Layout;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    modifier nonReentrant() {
        SecurityStorage.Layout storage s = SecurityStorage.layout();

        require(s.reentrantStatus != _ENTERED, "ReentrancyGuard: reentrant call");
        s.reentrantStatus = _ENTERED;
        _;
        s.reentrantStatus = _NOT_ENTERED;
    }
}

