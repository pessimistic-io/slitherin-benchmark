// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

interface IAddressBeacon {
  event AddressChange(bytes32 key, address addr);

  function set(bytes32 key, address addr) external;

  function get(bytes32 key) external view returns (address);
}

