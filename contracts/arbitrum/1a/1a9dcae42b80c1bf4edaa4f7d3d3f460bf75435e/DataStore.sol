// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {EnumerableSet} from "./EnumerableSet.sol";
import {EnumerableMap} from "./EnumerableMap.sol";

import {Keys} from "./Keys.sol";

import {IDataStore} from "./IDataStore.sol";

/// @title DataStore
/// @dev DataStore for all state values
contract DataStore is IDataStore {

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    // store for owner addresses
    mapping(address => bool) public owners;

    // store for uint values
    mapping(bytes32 => uint256) public uintValues;
    // store for int values
    mapping(bytes32 => int256) public intValues;
    // store for address values
    mapping(bytes32 => address) public addressValues;
    // store for bool values
    mapping(bytes32 => bool) public boolValues;
    // store for string values
    mapping(bytes32 => string) public stringValues;
    // store for bytes32 values
    mapping(bytes32 => bytes32) public bytes32Values;

    // store for uint[] values
    mapping(bytes32 => uint256[]) public uintArrayValues;
    // store for int[] values
    mapping(bytes32 => int256[]) public intArrayValues;
    // store for address[] values
    mapping(bytes32 => address[]) public addressArrayValues;
    // store for bool[] values
    mapping(bytes32 => bool[]) public boolArrayValues;
    // store for string[] values
    mapping(bytes32 => string[]) public stringArrayValues;
    // store for bytes32[] values
    mapping(bytes32 => bytes32[]) public bytes32ArrayValues;

    // store for address enumerable sets
    mapping(bytes32 => EnumerableSet.AddressSet) internal _addressSets;

    // store for address to uint enumerable maps
    mapping(bytes32 => EnumerableMap.AddressToUintMap) internal _addressToUintMaps;


    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice The ```constructor``` function is called on deployment
    /// @param _owner The owner address
    constructor(address _owner) {
        boolValues[Keys.PAUSED] = true;
        owners[_owner] = true;
    }

    // ============================================================================================
    // Modifiers
    // ============================================================================================

    /// @notice The ```onlyOwner``` modifier restricts functions to the owner
    modifier onlyOwner() {
        if (!owners[msg.sender]) revert Unauthorized();
        _;
    }

    // ============================================================================================
    // Owner Functions
    // ============================================================================================

    /// @inheritdoc IDataStore
    function updateOwnership(address _owner, bool _isActive) external onlyOwner {
        owners[_owner] = _isActive;

        emit UpdateOwnership(_owner, _isActive);
    }

    // ============================================================================================
    // Getters
    // ============================================================================================

    /// @inheritdoc IDataStore
    function getUint(bytes32 _key) external view returns (uint256) {
        return uintValues[_key];
    }

    /// @inheritdoc IDataStore
    function getInt(bytes32 _key) external view returns (int256) {
        return intValues[_key];
    }

    /// @inheritdoc IDataStore
    function getAddress(bytes32 _key) external view returns (address) {
        return addressValues[_key];
    }

    /// @inheritdoc IDataStore
    function getBool(bytes32 _key) external view returns (bool) {
        return boolValues[_key];
    }

    /// @inheritdoc IDataStore
    function getString(bytes32 _key) external view returns (string memory) {
        return stringValues[_key];
    }

    /// @inheritdoc IDataStore
    function getBytes32(bytes32 _key) external view returns (bytes32) {
        return bytes32Values[_key];
    }

    /// @inheritdoc IDataStore
    function getIntArray(bytes32 _key) external view returns (int256[] memory) {
        return intArrayValues[_key];
    }

    /// @inheritdoc IDataStore
    function getIntArrayAt(bytes32 _key, uint256 _index) external view returns (int256) {
        return intArrayValues[_key][_index];
    }

    /// @inheritdoc IDataStore
    function getUintArray(bytes32 _key) external view returns (uint256[] memory) {
        return uintArrayValues[_key];
    }

    /// @inheritdoc IDataStore
    function getUintArrayAt(bytes32 _key, uint256 _index) external view returns (uint256) {
        return uintArrayValues[_key][_index];
    }

    /// @inheritdoc IDataStore
    function getAddressArray(bytes32 _key) external view returns (address[] memory) {
        return addressArrayValues[_key];
    }

    /// @inheritdoc IDataStore
    function getAddressArrayAt(bytes32 _key, uint256 _index) external view returns (address) {
        return addressArrayValues[_key][_index];
    }

    /// @inheritdoc IDataStore
    function getBoolArray(bytes32 _key) external view returns (bool[] memory) {
        return boolArrayValues[_key];
    }

    /// @inheritdoc IDataStore
    function getBoolArrayAt(bytes32 _key, uint256 _index) external view returns (bool) {
        return boolArrayValues[_key][_index];
    }

    /// @inheritdoc IDataStore
    function getStringArray(bytes32 _key) external view returns (string[] memory) {
        return stringArrayValues[_key];
    }

    /// @inheritdoc IDataStore
    function getStringArrayAt(bytes32 _key, uint256 _index) external view returns (string memory) {
        return stringArrayValues[_key][_index];
    }

    /// @inheritdoc IDataStore
    function getBytes32Array(bytes32 _key) external view returns (bytes32[] memory) {
        return bytes32ArrayValues[_key];
    }

    /// @inheritdoc IDataStore
    function getBytes32ArrayAt(bytes32 _key, uint256 _index) external view returns (bytes32) {
        return bytes32ArrayValues[_key][_index];
    }

    /// @inheritdoc IDataStore
    function containsAddress(bytes32 _setKey, address _value) external view returns (bool) {
        return _addressSets[_setKey].contains(_value);
    }

    /// @inheritdoc IDataStore
    function getAddressCount(bytes32 _setKey) external view returns (uint256) {
        return _addressSets[_setKey].length();
    }

    /// @inheritdoc IDataStore
    function getAddressValueAt(bytes32 _setKey, uint256 _index) external view returns (address) {
        return _addressSets[_setKey].at(_index);
    }

    /// @inheritdoc IDataStore
    function containsAddressToUint(bytes32 _mapKey, address _key) external view returns (bool) {
        return _addressToUintMaps[_mapKey].contains(_key);
    }

    /// @inheritdoc IDataStore
    function getAddressToUintFor(bytes32 _mapKey, address _key) external view returns (uint256) {
        return _addressToUintMaps[_mapKey].get(_key);
    }

    /// @inheritdoc IDataStore
    function tryGetAddressToUintFor(bytes32 _mapKey, address _key) external view returns (bool, uint256) {
        return _addressToUintMaps[_mapKey].tryGet(_key);
    }

    /// @inheritdoc IDataStore
    function getAddressToUintCount(bytes32 _mapKey) external view returns (uint256) {
        return _addressToUintMaps[_mapKey].length();
    }

    /// @inheritdoc IDataStore
    function getAddressToUintAt(bytes32 _mapKey, uint256 _index) external view returns (address, uint256) {
        return _addressToUintMaps[_mapKey].at(_index);
    }

    // ============================================================================================
    // Setters
    // ============================================================================================

    /// @inheritdoc IDataStore
    function setUint(bytes32 _key, uint256 _value) external onlyOwner {
        uintValues[_key] = _value;
    }

    /// @inheritdoc IDataStore
    function incrementUint(bytes32 _key, uint256 _value) external onlyOwner {
        uintValues[_key] += _value;
    }

    /// @inheritdoc IDataStore
    function decrementUint(bytes32 _key, uint256 _value) external onlyOwner {
        uintValues[_key] -= _value;
    }

    /// @inheritdoc IDataStore
    function setInt(bytes32 _key, int256 _value) external onlyOwner {
        intValues[_key] = _value;
    }

    /// @inheritdoc IDataStore
    function incrementInt(bytes32 _key, int256 _value) external onlyOwner {
        intValues[_key] += _value;
    }

    /// @inheritdoc IDataStore
    function decrementInt(bytes32 _key, int256 _value) external onlyOwner {
        intValues[_key] -= _value;
    }

    /// @inheritdoc IDataStore
    function setAddress(bytes32 _key, address _value) external onlyOwner {
        addressValues[_key] = _value;
    }

    /// @inheritdoc IDataStore
    function setBool(bytes32 _key, bool _value) external onlyOwner {
        boolValues[_key] = _value;
    }

    /// @inheritdoc IDataStore
    function setString(bytes32 _key, string memory _value) external onlyOwner {
        stringValues[_key] = _value;
    }

    /// @inheritdoc IDataStore
    function setBytes32(bytes32 _key, bytes32 _value) external onlyOwner {
        bytes32Values[_key] = _value;
    }

    /// @inheritdoc IDataStore
    function setIntArray(bytes32 _key, int256[] memory _value) external onlyOwner {
        intArrayValues[_key] = _value;
    }

    /// @inheritdoc IDataStore
    function pushIntArray(bytes32 _key, int256 _value) external onlyOwner {
        intArrayValues[_key].push(_value);
    }

    /// @inheritdoc IDataStore
    function setIntArrayAt(bytes32 _key, uint256 _index, int256 _value) external onlyOwner {
        intArrayValues[_key][_index] = _value;
    }

    /// @inheritdoc IDataStore
    function incrementIntArrayAt(bytes32 _key, uint256 _index, int256 _value) external onlyOwner {
        intArrayValues[_key][_index] += _value;
    }

    /// @inheritdoc IDataStore
    function decrementIntArrayAt(bytes32 _key, uint256 _index, int256 _value) external onlyOwner {
        intArrayValues[_key][_index] -= _value;
    }

    /// @inheritdoc IDataStore
    function setUintArray(bytes32 _key, uint256[] memory _value) external onlyOwner {
        uintArrayValues[_key] = _value;
    }

    /// @inheritdoc IDataStore
    function pushUintArray(bytes32 _key, uint256 _value) external onlyOwner {
        uintArrayValues[_key].push(_value);
    }

    /// @inheritdoc IDataStore
    function setUintArrayAt(bytes32 _key, uint256 _index, uint256 _value) external onlyOwner {
        uintArrayValues[_key][_index] = _value;
    }

    /// @inheritdoc IDataStore
    function incrementUintArrayAt(bytes32 _key, uint256 _index, uint256 _value) external onlyOwner {
        uintArrayValues[_key][_index] += _value;
    }

    /// @inheritdoc IDataStore
    function decrementUintArrayAt(bytes32 _key, uint256 _index, uint256 _value) external onlyOwner {
        uintArrayValues[_key][_index] -= _value;
    }

    /// @inheritdoc IDataStore
    function setAddressArray(bytes32 _key, address[] memory _value) external onlyOwner {
        addressArrayValues[_key] = _value;
    }

    /// @inheritdoc IDataStore
    function pushAddressArray(bytes32 _key, address _value) external onlyOwner {
        addressArrayValues[_key].push(_value);
    }

    /// @inheritdoc IDataStore
    function setAddressArrayAt(bytes32 _key, uint256 _index, address _value) external onlyOwner {
        addressArrayValues[_key][_index] = _value;
    }

    /// @inheritdoc IDataStore
    function setBoolArray(bytes32 _key, bool[] memory _value) external onlyOwner {
        boolArrayValues[_key] = _value;
    }

    /// @inheritdoc IDataStore
    function pushBoolArray(bytes32 _key, bool _value) external onlyOwner {
        boolArrayValues[_key].push(_value);
    }

    /// @inheritdoc IDataStore
    function setBoolArrayAt(bytes32 _key, uint256 _index, bool _value) external onlyOwner {
        boolArrayValues[_key][_index] = _value;
    }

    /// @inheritdoc IDataStore
    function setStringArray(bytes32 _key, string[] memory _value) external onlyOwner {
        stringArrayValues[_key] = _value;
    }

    /// @inheritdoc IDataStore
    function pushStringArray(bytes32 _key, string memory _value) external onlyOwner {
        stringArrayValues[_key].push(_value);
    }

    /// @inheritdoc IDataStore
    function setStringArrayAt(bytes32 _key, uint256 _index, string memory _value) external onlyOwner {
        stringArrayValues[_key][_index] = _value;
    }

    /// @inheritdoc IDataStore
    function setBytes32Array(bytes32 _key, bytes32[] memory _value) external onlyOwner {
        bytes32ArrayValues[_key] = _value;
    }

    /// @inheritdoc IDataStore
    function pushBytes32Array(bytes32 _key, bytes32 _value) external onlyOwner {
        bytes32ArrayValues[_key].push(_value);
    }

    /// @inheritdoc IDataStore
    function setBytes32ArrayAt(bytes32 _key, uint256 _index, bytes32 _value) external onlyOwner {
        bytes32ArrayValues[_key][_index] = _value;
    }

    /// @inheritdoc IDataStore
    function addAddress(bytes32 _setKey, address _value) external onlyOwner {
        _addressSets[_setKey].add(_value);
    }

    /// @inheritdoc IDataStore
    function addAddressToUint(bytes32 _mapKey, address _key, uint256 _value) external onlyOwner returns (bool) {
        return _addressToUintMaps[_mapKey].set(_key, _value);
    }

    // ============================================================================================
    // Removers
    // ============================================================================================

    /// @inheritdoc IDataStore
    function removeUint(bytes32 _key) external onlyOwner {
        delete uintValues[_key];
    }

    function removeInt(bytes32 _key) external onlyOwner {
        delete intValues[_key];
    }

    /// @inheritdoc IDataStore
    function removeAddress(bytes32 _key) external onlyOwner {
        delete addressValues[_key];
    }

    /// @inheritdoc IDataStore
    function removeBool(bytes32 _key) external onlyOwner {
        delete boolValues[_key];
    }

    /// @inheritdoc IDataStore
    function removeString(bytes32 _key) external onlyOwner {
        delete stringValues[_key];
    }

    /// @inheritdoc IDataStore
    function removeBytes32(bytes32 _key) external onlyOwner {
        delete bytes32Values[_key];
    }

    /// @inheritdoc IDataStore
    function removeUintArray(bytes32 _key) external onlyOwner {
        delete uintArrayValues[_key];
    }

    /// @inheritdoc IDataStore
    function removeIntArray(bytes32 _key) external onlyOwner {
        delete intArrayValues[_key];
    }

    /// @inheritdoc IDataStore
    function removeAddressArray(bytes32 _key) external onlyOwner {
        delete addressArrayValues[_key];
    }

    /// @inheritdoc IDataStore
    function removeBoolArray(bytes32 _key) external onlyOwner {
        delete boolArrayValues[_key];
    }

    /// @inheritdoc IDataStore
    function removeStringArray(bytes32 _key) external onlyOwner {
        delete stringArrayValues[_key];
    }

    /// @inheritdoc IDataStore
    function removeBytes32Array(bytes32 _key) external onlyOwner {
        delete bytes32ArrayValues[_key];
    }

    /// @inheritdoc IDataStore
    function removeAddress(bytes32 _setKey, address _value) external onlyOwner {
        _addressSets[_setKey].remove(_value);
    }

    /// @inheritdoc IDataStore
    function removeUintToAddress(bytes32 _mapKey, address _key) external onlyOwner returns (bool) {
        return _addressToUintMaps[_mapKey].remove(_key);
    }
}
