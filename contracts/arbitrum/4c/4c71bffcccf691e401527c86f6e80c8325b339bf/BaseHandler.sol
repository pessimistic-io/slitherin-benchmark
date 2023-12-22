// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import {IHandlerContract} from "./IHandlerContract.sol";

/**
 * @title BaseHandler
 * @author Umami DAO
 * @notice Abstract base contract for implementing handler contracts with a delegate call restriction.
 * @dev Any contract inheriting from this contract must implement the IHandlerContract interface.
 */
abstract contract BaseHandler is IHandlerContract {
    address immutable SELF;
    error OnlyDelegateCall();

    constructor() {
        SELF = address(this);
    }

    /**
     * @notice Modifier to restrict functions to be called only via delegate call.
     * @dev Reverts if the function is called directly (not via delegate call).
     */
    modifier onlyDelegateCall() {
        if (address(this) == SELF) {
            revert OnlyDelegateCall();
        }
        _;
    }
}

