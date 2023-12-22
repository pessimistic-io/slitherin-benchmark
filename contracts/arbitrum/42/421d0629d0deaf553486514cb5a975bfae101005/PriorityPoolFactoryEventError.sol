// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface PriorityPoolFactoryEventError {

    // ---------------------------------------------------------------------------------------- //
    // *************************************** Events ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    event PoolCreated(
        uint256 poolId,
        address poolAddress,
        string protocolName,
        address protocolToken,
        uint256 maxCapacity,
        uint256 basePremiumRatio
    );

    event DynamicPoolUpdate(
        uint256 poolId,
        address pool,
        uint256 dynamicPoolCounter
    );

    event MaxCapacityUpdated(uint256 totalMaxCapacity);

    // ---------------------------------------------------------------------------------------- //
    // *************************************** Errors ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    error PriorityPoolFactory__OnlyExecutor(); // 5900a8a9
    error PriorityPoolFactory__OnlyPolicyCenter(); // b4e0f8d9
    error PriorityPoolFactory__OnlyOwnerOrExecutor(); // 6adaa0f9a
    error PriorityPoolFactory__OnlyPriorityPool(); // 3f193ee4
    error PriorityPoolFactory__OnlyIncidentReportOrExecutor(); // ae1aa57a
    error PriorityPoolFactory__PoolNotRegistered(); // 76213a28
    error PriorityPoolFactory__TokenAlreadyRegistered(); // 45d3e1f8
    error PriorityPoolFactory__AlreadyDynamicPool(); // 34c8f8b9
    error PriorityPoolFactory__NotOwnerOrFactory(); // 8bc3f382
    error PriorityPoolFactory__WrongLPToken(); // 00de38c2
}

