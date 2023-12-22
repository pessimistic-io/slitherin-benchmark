// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ================ IBaseOrchestratorReader =====================
// ==============================================================

// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {IBaseReader} from "./IBaseReader.sol";

/// @title IBaseOrchestratorReader
/// @dev Interface for BaseOrchestratorReader contract
interface IBaseOrchestratorReader is IBaseReader {

    // global

    function routeReader() external view returns (address);
    function routeSetter() external view returns (address);
    function platformAccountBalance(address _asset) external view returns (uint256);
    function isRouteTypeRegistered(bytes32 _routeTypeKey) external view returns (bool);

    // deployed contracts

    function routeFactory() external view returns (address);
    function multiSubscriber() external view returns (address);

    // keys

    function positionKey(address _route) external view returns (bytes32);

    // route

    function isWaitingForCallback(bytes32 _routeKey) external view returns (bool);
    function subscribedPuppetsCount(bytes32 _routeKey) external view returns (uint256);
    function puppetAt(bytes32 _routeKey, uint256 _index) external view returns (address);

    // puppets

    function puppetSubscriptions(address _puppet) external view returns (address[] memory);
}
