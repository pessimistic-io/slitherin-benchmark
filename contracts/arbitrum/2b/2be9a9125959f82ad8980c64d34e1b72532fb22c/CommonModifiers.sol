// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./CommonErrors.sol";
import "./IMiddleLayer.sol";

abstract contract CommonModifiers is CommonErrors {

    /**
    * @dev Guard variable for re-entrancy checks
    */
    bool internal entered;

    /**
    * @dev Prevents a contract from calling itself, directly or indirectly.
    */
    modifier nonReentrant() {
        if (entered) revert Reentrancy();
        entered = true;
        _;
        entered = false; // get a gas-refund post-Istanbul
    }
}

