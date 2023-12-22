// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ================= BaseOrchestratorReader =====================
// ==============================================================

// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {IBaseOrchestratorReader} from "./IBaseOrchestratorReader.sol";

import {BaseReader, Keys} from "./BaseReader.sol";

/// @title BaseOrchestratorReader
/// @dev Base contract for Orchestrator DataStore read functions
abstract contract BaseOrchestratorReader is IBaseOrchestratorReader, BaseReader {

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice The ```constructor``` function is called on deployment
    /// @param _dataStore The DataStore contract address
    /// @param _wntAddr The WNT contract address
    constructor(address _dataStore, address _wntAddr) BaseReader(_dataStore, _wntAddr) {}

    // ============================================================================================
    // View functions
    // ============================================================================================

    // global

    function routeReader() virtual external view returns (address) {}

    function routeSetter() external view returns (address) {
        return dataStore.getAddress(Keys.ROUTE_SETTER);
    }

    function platformAccountBalance(address _asset) external view returns (uint256) {
        return dataStore.getUint(Keys.platformAccountKey(_asset));
    }

    function isRouteTypeRegistered(bytes32 _routeTypeKey) external view returns (bool) {
        return dataStore.getBool(Keys.isRouteTypeRegisteredKey(_routeTypeKey));
    }

    // deployed contracts

    function routeFactory() external view returns (address) {
        return dataStore.getAddress(Keys.ROUTE_FACTORY);
    }

    function multiSubscriber() external view returns (address) {
        return dataStore.getAddress(Keys.MULTI_SUBSCRIBER);
    }

    // keys

    function positionKey(address _route) virtual public view returns (bytes32) {}

    // route

    function isWaitingForCallback(bytes32 _routeKey) virtual external view returns (bool);

    function subscribedPuppetsCount(bytes32 _routeKey) external view returns (uint256) {
        return dataStore.getAddressCount(Keys.routePuppetsKey(_routeKey));
    }

    function puppetAt(bytes32 _routeKey, uint256 _index) external view returns (address) {
        return dataStore.getAddressValueAt(Keys.routePuppetsKey(_routeKey), _index);
    }

    // puppets

    function puppetSubscriptions(address _puppet) external view returns (address[] memory) {
        address _route;
        uint256 _cleanSubscriptionCount = 0;
        bytes32 _puppetAllowancesKey = Keys.puppetAllowancesKey(_puppet);
        uint256 _dirtySubscriptionCount = dataStore.getAddressToUintCount(_puppetAllowancesKey);
        for (uint256 i = 0; i < _dirtySubscriptionCount; i++) {
            (_route,) = dataStore.getAddressToUintAt(_puppetAllowancesKey, i);
            if (puppetSubscriptionExpiry(_puppet, routeKey(_route)) > block.timestamp) {
                _cleanSubscriptionCount++;
            }
        }

        uint256 j = 0;
        address[] memory _subscriptions = new address[](_cleanSubscriptionCount);
        for (uint256 i = 0; i < _dirtySubscriptionCount; i++) {
            (_route,) = dataStore.getAddressToUintAt(_puppetAllowancesKey, i);
            if (puppetSubscriptionExpiry(_puppet, routeKey(_route)) > block.timestamp) {
                _subscriptions[j] = _route;
                j++;
            }
        }

        return _subscriptions;
    }
}
