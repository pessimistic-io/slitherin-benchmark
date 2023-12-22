pragma solidity ^0.8.0;
// Copyright 2023 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

/**
 * @title Interface for a NFT Registry of assets
 * @author Nevermined
 */
interface IExternalRegistry {

    function used(
        bytes32 _provId,
        bytes32 _did,
        address _agentId,
        bytes32 _activityId,
        bytes memory _signatureUsing,
        string memory _attributes
    )
    external
    returns (bool success);

    
    function getDIDOwner(bytes32 _did)
    external
    view
    returns (address didOwner);

    
    function isDIDProvider(
        bytes32 _did,
        address _provider
    )
    external
    view
    returns (bool);
}

