// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "./EnumerableMap.sol";

import "./Ownable.sol";
import "./ActionInfo.sol";

contract EternalStorage is Ownable {
  address internal writer;

  modifier onlyWriter() {
    require(msg.sender == writer);
    _;
  }

  constructor(address owner, address initialWriter) Ownable(owner) {
    writer = initialWriter;
  }

  event StorageWriterChanged(address oldWriter, address newWriter);

  function getWriter() public view returns (address) {
    return writer;
  }

  function setWriter(address newWriter) public onlyOwner {
    emit StorageWriterChanged(writer, newWriter);
    writer = newWriter;
  }

  mapping(bytes32 => uint256) uIntStorage;
  mapping(bytes32 => string) stringStorage;
  mapping(bytes32 => address) addressStorage;
  mapping(bytes32 => bytes) bytesStorage;
  mapping(bytes32 => bool) boolStorage;
  mapping(bytes32 => int256) intStorage;

  using EnumerableMap for EnumerableMap.UintToAddressMap;
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using EnumerableMap for EnumerableMap.Bytes32ToBytes32Map;
  using EnumerableMap for EnumerableMap.UintToUintMap;
  using EnumerableMap for EnumerableMap.Bytes32ToUintMap;
  mapping(bytes32 => EnumerableMap.UintToAddressMap) enumerableMapUintToAddressMapStorage;
  mapping(bytes32 => EnumerableMap.AddressToUintMap) enumerableMapAddressToUintMapStorage;
  mapping(bytes32 => EnumerableMap.Bytes32ToBytes32Map) enumerableMapBytes32ToBytes32MapStorage;
  mapping(bytes32 => EnumerableMap.UintToUintMap) enumerableMapUintToUintMapStorage;
  mapping(bytes32 => EnumerableMap.Bytes32ToUintMap) enumerableMapBytes32ToUintMapStorage;

  // *** Getter Methods ***
  function getUint(bytes32 _key) external view returns (uint256) {
    return uIntStorage[_key];
  }

  function getString(bytes32 _key) external view returns (string memory) {
    return stringStorage[_key];
  }

  function getAddress(bytes32 _key) external view returns (address) {
    return addressStorage[_key];
  }

  function getBytes(bytes32 _key) external view returns (bytes memory) {
    return bytesStorage[_key];
  }

  function getBool(bytes32 _key) external view returns (bool) {
    return boolStorage[_key];
  }

  function getInt(bytes32 _key) external view returns (int256) {
    return intStorage[_key];
  }

  // *** Setter Methods ***
  function setUint(bytes32 _key, uint256 _value) external onlyWriter {
    uIntStorage[_key] = _value;
  }

  function setString(bytes32 _key, string memory _value) external onlyWriter {
    stringStorage[_key] = _value;
  }

  function setAddress(bytes32 _key, address _value) external {
    addressStorage[_key] = _value;
  }

  function setBytes(bytes32 _key, bytes memory _value) external onlyWriter {
    bytesStorage[_key] = _value;
  }

  function setBool(bytes32 _key, bool _value) external onlyWriter {
    boolStorage[_key] = _value;
  }

  function setInt(bytes32 _key, int256 _value) external onlyWriter {
    intStorage[_key] = _value;
  }

  // *** Delete Methods ***
  function deleteUint(bytes32 _key) external onlyWriter {
    delete uIntStorage[_key];
  }

  function deleteString(bytes32 _key) external onlyWriter {
    delete stringStorage[_key];
  }

  function deleteAddress(bytes32 _key) external onlyWriter {
    delete addressStorage[_key];
  }

  function deleteBytes(bytes32 _key) external onlyWriter {
    delete bytesStorage[_key];
  }

  function deleteBool(bytes32 _key) external onlyWriter {
    delete boolStorage[_key];
  }

  function deleteInt(bytes32 _key) external onlyWriter {
    delete intStorage[_key];
  }

  // enumerable get

  function getEnumerableMapUintToAddress(bytes32 _key1, uint256 _key2) external view returns (address) {
    return enumerableMapUintToAddressMapStorage[_key1].get(_key2);
  }

  function getEnumerableMapAddressToUint(bytes32 _key1, address _key2) external view returns (uint256) {
    return enumerableMapAddressToUintMapStorage[_key1].get(_key2);
  }

  function getEnumerableMapBytes32ToBytes32Map(bytes32 _key1, bytes32 _key2) external view returns (bytes32) {
    return enumerableMapBytes32ToBytes32MapStorage[_key1].get(_key2);
  }

  function getEnumerableMapUintToUintMap(bytes32 _key1, uint256 _key2) external view returns (uint256) {
    return enumerableMapUintToUintMapStorage[_key1].get(_key2);
  }

  function getEnumerableMapBytes32ToUintMap(bytes32 _key1, bytes32 _key2) external view returns (uint256) {
    return enumerableMapBytes32ToUintMapStorage[_key1].get(_key2);
  }

  // enumerable tryGet

  function tryGetEnumerableMapUintToAddress(bytes32 _key1, uint256 _key2) external view returns (bool, address) {
    return enumerableMapUintToAddressMapStorage[_key1].tryGet(_key2);
  }

  function tryGetEnumerableMapAddressToUint(bytes32 _key1, address _key2) external view returns (bool, uint256) {
    return enumerableMapAddressToUintMapStorage[_key1].tryGet(_key2);
  }

  function tryGetEnumerableMapBytes32ToBytes32Map(bytes32 _key1, bytes32 _key2) external view returns (bool, bytes32) {
    return enumerableMapBytes32ToBytes32MapStorage[_key1].tryGet(_key2);
  }

  function tryGetEnumerableMapUintToUintMap(bytes32 _key1, uint256 _key2) external view returns (bool, uint256) {
    return enumerableMapUintToUintMapStorage[_key1].tryGet(_key2);
  }

  function tryGetEnumerableMapBytes32ToUintMap(bytes32 _key1, bytes32 _key2) external view returns (bool, uint256) {
    return enumerableMapBytes32ToUintMapStorage[_key1].tryGet(_key2);
  }

  // enumerable set

  function setEnumerableMapUintToAddress(
    bytes32 _key1,
    uint256 _key2,
    address _value
  ) external onlyWriter returns (bool) {
    return enumerableMapUintToAddressMapStorage[_key1].set(_key2, _value);
  }

  function setEnumerableMapAddressToUint(
    bytes32 _key1,
    address _key2,
    uint256 _value
  ) external onlyWriter returns (bool) {
    return enumerableMapAddressToUintMapStorage[_key1].set(_key2, _value);
  }

  function setEnumerableMapBytes32ToBytes32Map(
    bytes32 _key1,
    bytes32 _key2,
    bytes32 _value
  ) external onlyWriter returns (bool) {
    return enumerableMapBytes32ToBytes32MapStorage[_key1].set(_key2, _value);
  }

  function setEnumerableMapUintToUintMap(
    bytes32 _key1,
    uint256 _key2,
    uint256 _value
  ) external onlyWriter returns (bool) {
    return enumerableMapUintToUintMapStorage[_key1].set(_key2, _value);
  }

  function setEnumerableMapBytes32ToUintMap(
    bytes32 _key1,
    bytes32 _key2,
    uint256 _value
  ) external onlyWriter returns (bool) {
    return enumerableMapBytes32ToUintMapStorage[_key1].set(_key2, _value);
  }

  // enumerable remove

  function removeEnumerableMapUintToAddress(bytes32 _key1, uint256 _key2) external onlyWriter {
    enumerableMapUintToAddressMapStorage[_key1].remove(_key2);
  }

  function removeEnumerableMapAddressToUint(bytes32 _key1, address _key2) external onlyWriter {
    enumerableMapAddressToUintMapStorage[_key1].remove(_key2);
  }

  function removeEnumerableMapBytes32ToBytes32Map(bytes32 _key1, bytes32 _key2) external onlyWriter {
    enumerableMapBytes32ToBytes32MapStorage[_key1].remove(_key2);
  }

  function removeEnumerableMapUintToUintMap(bytes32 _key1, uint256 _key2) external onlyWriter {
    enumerableMapUintToUintMapStorage[_key1].remove(_key2);
  }

  function removeEnumerableMapBytes32ToUintMap(bytes32 _key1, bytes32 _key2) external onlyWriter {
    enumerableMapBytes32ToUintMapStorage[_key1].remove(_key2);
  }

  // enumerable contains

  function containsEnumerableMapUintToAddress(bytes32 _key1, uint256 _key2) external view returns (bool) {
    return enumerableMapUintToAddressMapStorage[_key1].contains(_key2);
  }

  function containsEnumerableMapAddressToUint(bytes32 _key1, address _key2) external view returns (bool) {
    return enumerableMapAddressToUintMapStorage[_key1].contains(_key2);
  }

  function containsEnumerableMapBytes32ToBytes32Map(bytes32 _key1, bytes32 _key2) external view returns (bool) {
    return enumerableMapBytes32ToBytes32MapStorage[_key1].contains(_key2);
  }

  function containsEnumerableMapUintToUintMap(bytes32 _key1, uint256 _key2) external view returns (bool) {
    return enumerableMapUintToUintMapStorage[_key1].contains(_key2);
  }

  function containsEnumerableMapBytes32ToUintMap(bytes32 _key1, bytes32 _key2) external view returns (bool) {
    return enumerableMapBytes32ToUintMapStorage[_key1].contains(_key2);
  }

  // enumerable length

  function lengthEnumerableMapUintToAddress(bytes32 _key1) external view returns (uint256) {
    return enumerableMapUintToAddressMapStorage[_key1].length();
  }

  function lengthEnumerableMapAddressToUint(bytes32 _key1) external view returns (uint256) {
    return enumerableMapAddressToUintMapStorage[_key1].length();
  }

  function lengthEnumerableMapBytes32ToBytes32Map(bytes32 _key1) external view returns (uint256) {
    return enumerableMapBytes32ToBytes32MapStorage[_key1].length();
  }

  function lengthEnumerableMapUintToUintMap(bytes32 _key1) external view returns (uint256) {
    return enumerableMapUintToUintMapStorage[_key1].length();
  }

  function lengthEnumerableMapBytes32ToUintMap(bytes32 _key1) external view returns (uint256) {
    return enumerableMapBytes32ToUintMapStorage[_key1].length();
  }

  // enumerable at

  function atEnumerableMapUintToAddress(bytes32 _key1, uint256 _index) external view returns (uint256, address) {
    return enumerableMapUintToAddressMapStorage[_key1].at(_index);
  }

  function atEnumerableMapAddressToUint(bytes32 _key1, uint256 _index) external view returns (address, uint256) {
    return enumerableMapAddressToUintMapStorage[_key1].at(_index);
  }

  function atEnumerableMapBytes32ToBytes32Map(bytes32 _key1, uint256 _index) external view returns (bytes32, bytes32) {
    return enumerableMapBytes32ToBytes32MapStorage[_key1].at(_index);
  }

  function atEnumerableMapUintToUintMap(bytes32 _key1, uint256 _index) external view returns (uint256, uint256) {
    return enumerableMapUintToUintMapStorage[_key1].at(_index);
  }

  function atEnumerableMapBytes32ToUintMap(bytes32 _key1, uint256 _index) external view returns (bytes32, uint256) {
    return enumerableMapBytes32ToUintMapStorage[_key1].at(_index);
  }
}

