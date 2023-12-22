// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {SafeOwnable} from "./SafeOwnable.sol";
import {IAddressBeacon} from "./IAddressBeacon.sol";

contract AddressBeacon is IAddressBeacon, SafeOwnable {
  mapping(bytes32 => address) private _keyToAddress;

  function set(bytes32 key, address addr) external override onlyOwner {
    _keyToAddress[key] = addr;
    emit AddressChange(key, addr);
  }

  function get(bytes32 key) external view override returns (address) {
    return _keyToAddress[key];
  }
}

