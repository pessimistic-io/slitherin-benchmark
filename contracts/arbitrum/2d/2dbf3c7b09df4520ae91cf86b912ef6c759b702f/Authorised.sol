// SPDX-License-Identifier: MIT
pragma solidity 0.8;

/// @title Authorised
/// @notice Restrict functions to whitelisted admins with the `onlyAdmin`
///     modifier. Deployer of contract is automatically added as an admin.
contract Authorised {
    /// @notice Whitelisted admins
    mapping(address => bool) public isAuthorised;

    error NotAuthorised(address culprit);

    constructor() {
        isAuthorised[msg.sender] = true;
    }

    /// @notice Restrict function to whitelisted admins only
    modifier onlyAuthorised() {
        if (!isAuthorised[msg.sender]) {
            revert NotAuthorised(msg.sender);
        }
        _;
    }

    /// @notice Set authorisation of a specific account
    /// @param toggle `true` to authorise account as an admin
    function authorise(address guy, bool toggle) public onlyAuthorised {
        isAuthorised[guy] = toggle;
    }
}

