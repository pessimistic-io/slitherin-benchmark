// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ==================== BaseReaderHelper ========================
// ==============================================================

// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {Keys} from "./Keys.sol";

import {IDataStore} from "./IDataStore.sol";

library BaseReaderHelper {

    function puppetSubscriptionExpiry(IDataStore _dataStore, address _puppet, bytes32 _routeKey) public view returns (uint256) {
        uint256 _expiry = _dataStore.getUint(Keys.puppetSubscriptionExpiryKey(_puppet, _routeKey));
        if (_expiry > block.timestamp) {
            return _expiry;
        } else {
            return 0;
        }
    }

    function routeKey(IDataStore _dataStore, address _trader, bytes32 _routeTypeKey) external view returns (bytes32) {
        address _collateralToken = _dataStore.getAddress(Keys.routeTypeCollateralTokenKey(_routeTypeKey));
        address _indexToken = _dataStore.getAddress(Keys.routeTypeIndexTokenKey(_routeTypeKey));
        bool _isLong = _dataStore.getBool(Keys.routeTypeIsLongKey(_routeTypeKey));
        return keccak256(abi.encode(_trader, _collateralToken, _indexToken, _isLong));
    }

    function subscribedPuppets(IDataStore _dataStore, bytes32 _routeKey) external view returns (address[] memory) {
        bytes32 _routePuppetsKey = Keys.routePuppetsKey(_routeKey);
        uint256 _dirtyPuppetsLength = _dataStore.getAddressCount(_routePuppetsKey);
        address[] memory _dirtyPuppets = new address[](_dirtyPuppetsLength);
        uint256 _cleanCount = 0;
        for (uint256 i = 0; i < _dirtyPuppetsLength; i++) {
            address _puppet = _dataStore.getAddressValueAt(_routePuppetsKey, i);
            _dirtyPuppets[i] = _puppet;
            if (puppetSubscriptionExpiry(_dataStore, _puppet, _routeKey) > block.timestamp) _cleanCount++;
        }

        uint256 j = 0;
        address[] memory _cleanPuppets = new address[](_cleanCount);
        for (uint256 i = 0; i < _dirtyPuppetsLength; i++) {
            address _puppet = _dirtyPuppets[i];
            if (puppetSubscriptionExpiry(_dataStore, _puppet, _routeKey) > block.timestamp) {
                _cleanPuppets[j] = _puppet;
                j++;
            }
        }

        return _cleanPuppets;
    }
}
