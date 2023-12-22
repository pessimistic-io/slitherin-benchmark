// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AccountInitializer} from "./AccountInitializer.sol";
import {IPermissions} from "./IPermissions.sol";
import {Operations} from "./Operations.sol";

import {AccountGroupLib} from "./AccountGroupLib.sol";

/// @notice Verify sender has INITIALIZE_ACCOUNT permission
contract PermissionGatedInitializer is AccountInitializer {
    /// @dev delegatecall'ed by 6551 Account
    function _authenticateInitialization(address, bytes memory initData)
        internal
        view
        override
        returns (bytes memory)
    {
        AccountGroupLib.AccountParams memory params = AccountGroupLib.accountParams();
        // Verify entity calling the 6551 Account (msg.sender) has INITIALIZE_ACCOUNT permission from Account Group
        IPermissions(params.accountGroup).checkPermission(Operations.INITIALIZE_ACCOUNT, msg.sender);

        return initData;
    }
}

