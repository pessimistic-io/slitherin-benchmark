// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IStorageAddresses {
    function setAddress(address _finder, address _storageAddress, bool _force) external;

    function setAddress(bytes32 _key, address _storageAddress, bool _force) external;

    function getAddress(address _finder) external view returns (address);

    function getAddress(bytes32 _key) external view returns (address);
}

