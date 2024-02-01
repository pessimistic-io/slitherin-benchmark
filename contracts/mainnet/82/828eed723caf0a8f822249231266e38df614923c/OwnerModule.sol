//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "./Ownable.sol";
import "./InitializableMixin.sol";
import "./IOwnerModule.sol";

/**
 * @title Module for giving a system owner based access control.
 * See IOwnerModule.
 */
contract OwnerModule is Ownable, IOwnerModule {
    // solhint-disable-next-line no-empty-blocks
    constructor() Ownable(address(0)) {
        // empty intentionally
    }

    // no impl intentionally
}

