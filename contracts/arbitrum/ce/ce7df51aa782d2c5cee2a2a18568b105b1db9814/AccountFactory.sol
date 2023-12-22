// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {BeaconProxy} from "./BeaconProxy.sol";
import {IAccount} from "./IAccount.sol";
import {IAccountFactory} from "./IAccountFactory.sol";

/**
    @title Account Factory
    @notice Factory that creates Account as a beacon proxy
*/
contract AccountFactory is IAccountFactory {

    /* -------------------------------------------------------------------------- */
    /*                               STATE VARIABLES                              */
    /* -------------------------------------------------------------------------- */

    /// @notice Address of account beacon
    address public beacon;

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */

    /**
        @notice Contract constructor
        @param _beacon address of account beacon
    */
    constructor (address _beacon) {
        beacon = _beacon;
    }

    /* -------------------------------------------------------------------------- */
    /*                             EXTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */

    /**
        @notice Account creator
        @param accountManager Address of account manager
        @dev Emits AccountCreated(account, accountManager) event
        @return account Address of account created
    */
    function create(address accountManager)
        external
        returns (address account)
    {
        account = address(new BeaconProxy(beacon, accountManager));
        emit AccountCreated(account, accountManager);
    }
}

