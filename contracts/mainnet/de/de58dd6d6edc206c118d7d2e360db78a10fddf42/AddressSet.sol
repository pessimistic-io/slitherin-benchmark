/*
 * This file is part of the Qomet Technologies contracts (https://github.com/qomet-tech/contracts).
 * Copyright (c) 2022 Qomet Technologies (https://qomet.tech)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
// SPDX-License-Identifier: GNU General Public License v3.0

pragma solidity 0.8.1;

/// @author Kam Amini <kam@arteq.io>
///
/// @notice Use at your own risk. Just got the basic
///         setIdea from: https://github.com/solsetIdstate-network/solsetIdstate-solsetIdity
library AddressSetStorage {

    struct AddressSet {
        // list of address items
        address[] items;
        // address > index in the items array
        mapping(address => uint256) itemsIndex;
        // address > true if removed
        mapping(address => bool) removedItems;
    }

    struct Zone {
        // set ID > set object
        mapping(bytes32 => AddressSet) sets;
    }

    struct Layout {
        // zone ID > zone object
        mapping(bytes32 => Zone) zones;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("qomet-tech.contracts.lib.address-set.storage");

    function layout() internal pure returns (Layout storage s) {
        bytes32 slot = STORAGE_SLOT;
        /* solhint-disable no-inline-assembly */
        assembly {
            s.slot := slot
        }
        /* solhint-enable no-inline-assembly */
    }
}

library AddressSetLib {

    function _hasItem(
        bytes32 zoneId,
        bytes32 setId,
        address item
    ) internal view returns (bool) {
        return __s2(zoneId, setId).itemsIndex[item] > 0 &&
            !__s2(zoneId, setId).removedItems[item];
    }

    function _getItemsCount(
        bytes32 zoneId,
        bytes32 setId
    ) internal view returns (uint256) {
        return __s2(zoneId, setId).items.length;
    }

    function _getItems(
        bytes32 zoneId,
        bytes32 setId
    ) internal view returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < __s2(zoneId, setId).items.length; i++) {
            address item = __s2(zoneId, setId).items[i];
            if (!__s2(zoneId, setId).removedItems[item]) {
                count++;
            }
        }
        address[] memory results = new address[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < __s2(zoneId, setId).items.length; i++) {
            address item = __s2(zoneId, setId).items[i];
            if (!__s2(zoneId, setId).removedItems[item]) {
                results[j] = item;
                j += 1;
            }
        }
        return results;
    }

    function _addItem(
        bytes32 zoneId,
        bytes32 setId,
        address item
    ) internal returns (bool) {
        if (__s2(zoneId, setId).itemsIndex[item] == 0) {
            __s2(zoneId, setId).items.push(item);
            __s2(zoneId, setId).itemsIndex[item] = __s2(zoneId, setId).items.length;
            return true;
        } else if (__s2(zoneId, setId).removedItems[item]) {
            __s2(zoneId, setId).removedItems[item] = false;
            return true;
        }
        return false;
    }

    function _removeItem(
        bytes32 zoneId,
        bytes32 setId,
        address item
    ) internal returns (bool) {
        if (
            __s2(zoneId, setId).itemsIndex[item] > 0 &&
            !__s2(zoneId, setId).removedItems[item]
         ) {
            __s2(zoneId, setId).removedItems[item] = true;
            return true;
        }
        return false;
    }

    function __s2(
        bytes32 zoneId,
        bytes32 setId
    ) private view returns (AddressSetStorage.AddressSet storage) {
        return __s().zones[zoneId].sets[setId];
    }

    function __s() private pure returns (AddressSetStorage.Layout storage) {
        return AddressSetStorage.layout();
    }
}


