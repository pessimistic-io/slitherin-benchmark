// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

interface IDataStore {
    function getUint(bytes32 key) external view returns (uint256);
    function setUint(bytes32 key, uint256 value) external returns (uint256);
    function removeUint(bytes32 key) external;
    function applyDeltaToUint(bytes32 key, int256 value, string calldata errorMessage) external returns (uint256);
    function applyDeltaToUint(bytes32 key, uint256 value) external returns (uint256);
    function applyBoundedDeltaToUint(bytes32 key, int256 value) external returns (uint256);
    function incrementUint(bytes32 key, uint256 value) external returns (uint256);
    function decrementUint(bytes32 key, uint256 value) external returns (uint256);

    function getInt(bytes32 key) external view returns (int256);
    function setInt(bytes32 key, int256 value) external returns (int256);
    function removeInt(bytes32 key) external;
    function applyDeltaToInt(bytes32 key, int256 value) external returns (int256);
    function incrementInt(bytes32 key, int256 value) external returns (int256);
    function decrementInt(bytes32 key, int256 value) external returns (int256);

    function getAddress(bytes32 key) external view returns (address);
    function setAddress(bytes32 key, address value) external returns (address);
    function removeAddress(bytes32 key) external;

    function getBool(bytes32 key) external view returns (bool);
    function setBool(bytes32 key, bool value) external returns (bool);
    function removeBool(bytes32 key) external;

    function getString(bytes32 key) external view returns (string memory);
    function setString(bytes32 key, string calldata value) external returns (string memory);
    function removeString(bytes32 key) external;

    function getBytes32(bytes32 key) external view returns (bytes32);
    function setBytes32(bytes32 key, bytes32 value) external returns (bytes32);
    function removeBytes32(bytes32 key) external;

    function getUintArray(bytes32 key) external view returns (uint256[] memory);
    function setUintArray(bytes32 key, uint256[] memory value) external;
    function removeUintArray(bytes32 key) external;

    function getIntArray(bytes32 key) external view returns (int256[] memory);
    function setIntArray(bytes32 key, int256[] memory value) external;
    function removeIntArray(bytes32 key) external;

    function getAddressArray(bytes32 key) external view returns (address[] memory);
    function setAddressArray(bytes32 key, address[] memory value) external;
    function removeAddressArray(bytes32 key) external;

    function getBoolArray(bytes32 key) external view returns (bool[] memory);
    function setBoolArray(bytes32 key, bool[] memory value) external;
    function removeBoolArray(bytes32 key) external;

    function getStringArray(bytes32 key) external view returns (string[] memory);
    function setStringArray(bytes32 key, string[] memory value) external;
    function removeStringArray(bytes32 key) external;

    function getBytes32Array(bytes32 key) external view returns (bytes32[] memory);
    function setBytes32Array(bytes32 key, bytes32[] memory value) external;
    function removeBytes32Array(bytes32 key) external;

    function containsBytes32(bytes32 setKey, bytes32 value) external view returns (bool);
    function getBytes32Count(bytes32 setKey) external view returns (uint256);
    function getBytes32ValuesAt(bytes32 setKey, uint256 start, uint256 end) external view returns (bytes32[] memory);
    function addBytes32(bytes32 setKey, bytes32 value) external;
    function removeBytes32(bytes32 setKey, bytes32 value) external;

    function containsAddress(bytes32 setKey, address value) external view returns (bool);
    function getAddressCount(bytes32 setKey) external view returns (uint256);
    function getAddressValuesAt(bytes32 setKey, uint256 start, uint256 end) external view returns (address[] memory);
    function addAddress(bytes32 setKey, address value) external;
    function removeAddress(bytes32 setKey, address value) external;

    function containsUint(bytes32 setKey, uint256 value) external view returns (bool);
    function getUintCount(bytes32 setKey) external view returns (uint256);
    function getUintValuesAt(bytes32 setKey, uint256 start, uint256 end) external view returns (uint256[] memory);
    function addUint(bytes32 setKey, uint256 value) external;
    function removeUint(bytes32 setKey, uint256 value) external;
}
