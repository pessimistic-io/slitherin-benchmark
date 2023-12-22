// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {SafeOwnable} from "./SafeOwnable.sol";
import {IUintBeacon} from "./IUintBeacon.sol";

contract UintBeacon is IUintBeacon, SafeOwnable {
  mapping(bytes32 => uint256) private _keyToValue;

  function set(bytes32 key, uint256 value) external override onlyOwner {
    _keyToValue[key] = value;
    emit UintChange(key, value);
  }

  function get(bytes32 key) external view override returns (uint256) {
    return _keyToValue[key];
  }
}

