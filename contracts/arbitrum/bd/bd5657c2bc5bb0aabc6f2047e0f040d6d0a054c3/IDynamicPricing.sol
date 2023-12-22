pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

/**
 * @title Interface that can implement different contracts implementing some kind of 
 * dynamic pricing functionality.
 * @author Nevermined
 */
interface IDynamicPricing {

    enum DynamicPricingState { NotStarted, Finished, InProgress, Aborted }

    function getPricingType(
    )
    external
    view
    returns(bytes32);

    function getPrice(
        bytes32 did
    )
    external
    view
    returns(uint256);

    function getTokenAddress(
        bytes32 did
    )
    external
    view
    returns(address);

    function getStatus(
        bytes32 did
    )
    external
    view
    returns(DynamicPricingState, uint256, address);

    function canBePurchased(
        bytes32 did
    )
    external
    view
    returns(bool);

    function withdraw(
        bytes32 did,
        address withdrawAddress
    )
    external
    returns(bool);

}

