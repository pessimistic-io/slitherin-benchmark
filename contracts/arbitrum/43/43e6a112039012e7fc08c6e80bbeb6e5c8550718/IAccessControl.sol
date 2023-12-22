pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0



/**
 * @title Access Control Interface
 * @author Nevermined
 */
interface IAccessControl {

    /**
    * @notice It checks if an address (`_address`) has access to a certain asset (`_did`) 
    * @param _address address of the account to check if has address
    * @param _did unique identifier of the asset
    * @return permissionGranted is true if the `_address` has access to the `_did`
    */    
    function checkPermissions(
        address _address,
        bytes32 _did
    )
    external view
    returns (bool permissionGranted);

    /**
    * @notice Grants access permissions to an `_address` to a specific `_did`
    * @dev `grantPermission` is called only by the `_did` owner or provider
    * @param _address address of the account to check if has address
    * @param _did unique identifier of the asset     
    */
    function grantPermission(
        address _address,
        bytes32 _did
    )
    external;
    
    /**
    * @notice Renounce access permissions to an `_address` to a specific `_did`
    * @dev `renouncePermission` is called only by the `_did` owner or provider
    * @param _address address of the account to check if has address
    * @param _did unique identifier of the asset     
    */    
    function renouncePermission(
        address _address,
        bytes32 _did
    )
    external;    
}

