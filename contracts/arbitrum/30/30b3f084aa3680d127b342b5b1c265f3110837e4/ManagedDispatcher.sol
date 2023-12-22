// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Copyright (C) 2023 VALK
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.18;
import "./ISmartWallet.sol";
import "./IDispatcher.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";
import { Account, OWNED_SMART_WALLET_ACCOUNT, END_USER_ACCOUNT } from "./Account.sol";
// import "hardhat/console.sol";

struct Key {
  uint8 executorType;
  bytes20 target;
  bytes4 selector;
}

abstract contract ManagedDispatcher is IDispatcher, Ownable {
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using EnumerableSet for EnumerableSet.AddressSet;

	mapping(bytes32 => address) internal targetsByKeys;
  mapping(address => EnumerableSet.Bytes32Set) internal keysByTargets;
  EnumerableSet.AddressSet internal targets;

	event SetTarget(uint8 dispatchType, bytes20 indexed target, bytes4 indexed selector, address indexed newValue, address prevValue);

  /**
    Use fill target and selector for calls processed by wallet.exec.
    Use empty target for calls processed by wallet.fallback.
    Use empty target and empty selector for default target.
    Use empty dispatchedTarget to delete respective value.

    Set target != dispatchedTarget to implement target mapping. 
    I.e. names to addresses mapping or old script version to new script version mapping.

    Delete all values and set default target = [updater script] to update dispatcher in user wallets.
   */
	function _setTarget(
    uint8 executorType,
		bytes20 target,
		bytes4 selector,
		address dispatchedTarget
	) internal {
		bytes32 key = bytes32(abi.encodePacked(executorType, target, selector));
		address oldDispatchedTarget = targetsByKeys[key];
    if (dispatchedTarget == oldDispatchedTarget) {
      return;
    }

		targetsByKeys[key] = dispatchedTarget;

    if (oldDispatchedTarget != address(0)) {
      keysByTargets[oldDispatchedTarget].remove(key);
      if (keysByTargets[oldDispatchedTarget].length() == 0) {
        targets.remove(oldDispatchedTarget);
      }
    }

    if (dispatchedTarget != address(0)) {
      keysByTargets[dispatchedTarget].add(key);
      targets.add(dispatchedTarget);
    }

    // console.log("set target %s, sig %s to %s", address(target), address(bytes20(selector)), dispatchedTarget);
    emit SetTarget(executorType, target, selector, dispatchedTarget, oldDispatchedTarget);
	}

  function setTarget(
    uint8 executorType,
		bytes20 target,
		bytes4 selector,
		address dispatchedTarget
	) external onlyOwner {
		_setTarget(executorType, target, selector, dispatchedTarget);
	}

  function setTargets(
		Key[] calldata keys,
		address dispatchedTarget
	) external onlyOwner {
		for (uint i = 0; i < keys.length; i++) {
      Key memory key = keys[i];
			_setTarget(key.executorType, key.target, key.selector, dispatchedTarget);
		}
	}

  function getTarget(
    uint8 executorType,
		bytes20 target,
		bytes4 selector
	) public view returns (address storedTarget) {
		bytes32 key = bytes32(abi.encodePacked(executorType, target, selector));
    return targetsByKeys[key];
	}

  function getTargeOrDefault(
    uint8 executorType,
		bytes20 target,
		bytes4 selector
	) internal view returns (address dispatchedTarget) {
    dispatchedTarget = getTarget(executorType, target, selector);
    if (dispatchedTarget == address(0)) {
      // use default target
      dispatchedTarget = getTarget(executorType, bytes20(0), bytes4(0));
    }
	}

  function getTargets() public view returns (address[] memory storedTargets) {
    return targets.values();
  }

  function getKeyByTarget(
    address dispatchedTarget,
    uint index
	) public view returns (Key memory key) {
    bytes32 packedKey = keysByTargets[dispatchedTarget].at(index);
    return unpackKey(packedKey);
	}

  function getKeysByTarget(
    address dispatchedTarget
	) public view returns (Key[] memory keys) {
    bytes32[] memory packedKeys = keysByTargets[dispatchedTarget].values();
    keys = new Key[](packedKeys.length);
    for(uint i = 0; i < keys.length; i++) {
      keys[i] = unpackKey(packedKeys[i]);
    }
	}

  function unpackKey(bytes32 packedKey) internal pure returns (Key memory key) {
    key.executorType = uint8(bytes1(packedKey));
    packedKey = packedKey << 8;
    key.target = bytes20(packedKey);
    packedKey = packedKey << 160;
    key.selector = bytes4(packedKey);
  }
}

