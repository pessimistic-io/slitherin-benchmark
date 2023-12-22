// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ========================= IDataStore =========================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

interface IDataStore {

    // ============================================================================================
    // Owner Functions
    // ============================================================================================

    /// @notice Update the ownership of the contract
    /// @param _owner The owner address
    /// @param _isActive The status of the owner
    function updateOwnership(address _owner, bool _isActive) external;

    // ============================================================================================
    // Getters
    // ============================================================================================

    /// @dev get the uint value for the given key
    /// @param _key the key of the value
    /// @return _value the uint value for the key
    function getUint(bytes32 _key) external view returns (uint256 _value);

    /// @dev get the int value for the given key
    /// @param _key the key of the value
    /// @return _value the int value for the key
    function getInt(bytes32 _key) external view returns (int256 _value);

    /// @dev get the address value for the given key
    /// @param _key the key of the value
    /// @return _value the address value for the key
    function getAddress(bytes32 _key) external view returns (address _value);

    /// @dev get the bool value for the given key
    /// @param _key the key of the value
    /// @return _value the bool value for the key
    function getBool(bytes32 _key) external view returns (bool _value);

    /// @dev get the string value for the given key
    /// @param _key the key of the value
    /// @return _value the string value for the key
    function getString(bytes32 _key) external view returns (string memory _value);

    /// @dev get the bytes32 value for the given key
    /// @param _key the key of the value
    /// @return _value the bytes32 value for the key
    function getBytes32(bytes32 _key) external view returns (bytes32 _value);

    /// @dev get the int array for the given key
    /// @param _key the key of the int array
    /// @return _value the int array for the key
    function getIntArray(bytes32 _key) external view returns (int256[] memory _value);

    /// @dev get the int array for the given key and index
    /// @param _key the key of the int array
    /// @param _index the index of the int array
    function getIntArrayAt(bytes32 _key, uint256 _index) external view returns (int256);

    /// @dev get the uint array for the given key
    /// @param _key the key of the uint array
    /// @return _value the uint array for the key
    function getUintArray(bytes32 _key) external view returns (uint256[] memory _value);

    /// @dev get the uint array for the given key and index
    /// @param _key the key of the uint array
    /// @param _index the index of the uint array
    function getUintArrayAt(bytes32 _key, uint256 _index) external view returns (uint256);

    /// @dev get the address array for the given key
    /// @param _key the key of the address array
    /// @return _value the address array for the key
    function getAddressArray(bytes32 _key) external view returns (address[] memory _value);

    /// @dev get the address array for the given key and index
    /// @param _key the key of the address array
    /// @param _index the index of the address array
    function getAddressArrayAt(bytes32 _key, uint256 _index) external view returns (address);

    /// @dev get the bool array for the given key
    /// @param _key the key of the bool array
    /// @return _value the bool array for the key
    function getBoolArray(bytes32 _key) external view returns (bool[] memory _value);

    /// @dev get the bool array for the given key and index
    /// @param _key the key of the bool array
    /// @param _index the index of the bool array
    function getBoolArrayAt(bytes32 _key, uint256 _index) external view returns (bool);

    /// @dev get the string array for the given key
    /// @param _key the key of the string array
    /// @return _value the string array for the key
    function getStringArray(bytes32 _key) external view returns (string[] memory _value);

    /// @dev get the string array for the given key and index
    /// @param _key the key of the string array
    /// @param _index the index of the string array
    function getStringArrayAt(bytes32 _key, uint256 _index) external view returns (string memory);

    /// @dev get the bytes32 array for the given key
    /// @param _key the key of the bytes32 array
    /// @return _value the bytes32 array for the key
    function getBytes32Array(bytes32 _key) external view returns (bytes32[] memory _value);

    /// @dev get the bytes32 array for the given key and index
    /// @param _key the key of the bytes32 array
    /// @param _index the index of the bytes32 array
    function getBytes32ArrayAt(bytes32 _key, uint256 _index) external view returns (bytes32);

    /// @dev check whether the given value exists in the set
    /// @param _setKey the key of the set
    /// @param _value the value to check
    /// @return _exists whether the value exists in the set
    function containsAddress(bytes32 _setKey, address _value) external view returns (bool _exists);

    /// @dev get the length of the set
    /// @param _setKey the key of the set
    /// @return _length the length of the set
    function getAddressCount(bytes32 _setKey) external view returns (uint256 _length);

    /// @dev get the values of the set at the given index
    /// @param _setKey the key of the set
    /// @param _index the index of the value to return
    /// @return _value the value at the given index
    function getAddressValueAt(bytes32 _setKey, uint256 _index) external view returns (address _value);

    /// @dev check whether the key exists in the map
    /// @param _mapKey the key of the map
    /// @param _key the key to check
    /// @return _exists whether the key exists in the map
    function containsAddressToUint(bytes32 _mapKey, address _key) external view returns (bool _exists);

    /// @dev get the value associated with key. reverts if the key does not exist
    /// @param _mapKey the key of the map
    /// @param _key the key to get the value for
    /// @return _value the value associated with the key
    function getAddressToUintFor(bytes32 _mapKey, address _key) external view returns (uint256 _value);

    /// @dev tries to returns the value associated with key. does not revert if key is not in the map
    /// @param _mapKey the key of the map
    /// @param _key the key to get the value for
    /// @return _exists whether the key exists in the map
    /// @return _value the value associated with the key
    function tryGetAddressToUintFor(bytes32 _mapKey, address _key) external view returns (bool _exists, uint256 _value);

    /// @dev get the length of the map
    /// @param _mapKey the key of the map
    /// @return _length the length of the map
    function getAddressToUintCount(bytes32 _mapKey) external view returns (uint256 _length);

    /// @dev get the key and value pairs of the map in the given index
    /// @param _mapKey the key of the map
    /// @param _index the index of the key and value pair to return
    /// @return _key the key at the given index
    /// @return _value the value at the given index
    function getAddressToUintAt(bytes32 _mapKey, uint256 _index) external view returns (address _key, uint256 _value);

    /// ============================================================================================
    /// Setters
    /// ============================================================================================

    /// @dev set the uint value for the given key
    /// @param _key the key of the value
    /// @param _value the value to set
    function setUint(bytes32 _key, uint256 _value) external;

    /// @dev add the input uint value to the existing uint value
    /// @param _key the key of the value
    /// @param _value the amount to add to the existing uint value
    function incrementUint(bytes32 _key, uint256 _value) external;

    /// @dev subtract the input uint value from the existing uint value
    /// @param _key the key of the value
    /// @param _value the amount to subtract from the existing uint value
    function decrementUint(bytes32 _key, uint256 _value) external;

    /// @dev set the int value for the given key
    /// @param _key the key of the value
    /// @param _value the value to set
    function setInt(bytes32 _key, int256 _value) external;

    /// @dev add the input int value to the existing int value
    /// @param _key the key of the value
    /// @param _value the amount to add to the existing int value
    function incrementInt(bytes32 _key, int256 _value) external;

    /// @dev subtract the input int value from the existing int value
    /// @param _key the key of the value
    /// @param _value the amount to subtract from the existing int value
    function decrementInt(bytes32 _key, int256 _value) external;

    /// @dev set the address value for the given key
    /// @param _key the key of the value
    /// @param _value the value to set
    function setAddress(bytes32 _key, address _value) external;

    /// @dev set the bool value for the given key
    /// @param _key the key of the value
    /// @param _value the value to set
    function setBool(bytes32 _key, bool _value) external;

    /// @dev set the string value for the given key
    /// @param _key the key of the value
    /// @param _value the value to set
    function setString(bytes32 _key, string memory _value) external;

    /// @dev set the bytes32 value for the given key
    /// @param _key the key of the value
    /// @param _value the value to set
    function setBytes32(bytes32 _key, bytes32 _value) external;

    /// @dev set the int array for the given key
    /// @param _key the key of the int array
    /// @param _value the value of the int array
    function setIntArray(bytes32 _key, int256[] memory _value) external;

    /// @dev push the input int value to the existing int array
    /// @param _key the key of the int array
    /// @param _value the value to push to the existing int array
    function pushIntArray(bytes32 _key, int256 _value) external;

    /// @dev set a specific index of the int array with the input value
    /// @param _key the key of the int array
    /// @param _index the index of the int array to set
    /// @param _value the value to set
    function setIntArrayAt(bytes32 _key, uint256 _index, int256 _value) external;

    /// @dev increment the int value at the given index of the int array with the input value
    /// @param _key the key of the int array
    /// @param _index the index of the int array to increment
    /// @param _value the value to increment
    function incrementIntArrayAt(bytes32 _key, uint256 _index, int256 _value) external;

    /// @dev decrement the int value at the given index of the int array with the input value
    /// @param _key the key of the int array
    /// @param _index the index of the int array to decrement
    /// @param _value the value to decrement
    function decrementIntArrayAt(bytes32 _key, uint256 _index, int256 _value) external;

    /// @dev set the uint array for the given key
    /// @param _key the key of the uint array
    /// @param _value the value of the uint array
    function setUintArray(bytes32 _key, uint256[] memory _value) external;

    /// @dev push the input uint value to the existing uint array
    /// @param _key the key of the uint array
    /// @param _value the value to push to the existing uint array
    function pushUintArray(bytes32 _key, uint256 _value) external;

    /// @dev set a specific index of the uint array with the input value
    /// @param _key the key of the uint array
    /// @param _index the index of the uint array to set
    /// @param _value the value to set
    function setUintArrayAt(bytes32 _key, uint256 _index, uint256 _value) external;

    /// @dev increment the uint value at the given index of the uint array with the input value
    /// @param _key the key of the uint array
    /// @param _index the index of the uint array to increment
    /// @param _value the value to increment
    function incrementUintArrayAt(bytes32 _key, uint256 _index, uint256 _value) external;

    /// @dev decrement the uint value at the given index of the uint array with the input value
    /// @param _key the key of the uint array
    /// @param _index the index of the uint array to decrement
    /// @param _value the value to decrement
    function decrementUintArrayAt(bytes32 _key, uint256 _index, uint256 _value) external;

    /// @dev set the address array for the given key
    /// @param _key the key of the address array
    /// @param _value the value of the address array
    function setAddressArray(bytes32 _key, address[] memory _value) external;

    /// @dev push the input address value to the existing address array
    /// @param _key the key of the address array
    /// @param _value the value to push to the existing address array
    function pushAddressArray(bytes32 _key, address _value) external;

    /// @dev set a specific index of the address array with the input value
    /// @param _key the key of the address array
    /// @param _index the index of the address array to set
    /// @param _value the value to set
    function setAddressArrayAt(bytes32 _key, uint256 _index, address _value) external;

    /// @dev set the bool array for the given key
    /// @param _key the key of the bool array
    /// @param _value the value of the bool array
    function setBoolArray(bytes32 _key, bool[] memory _value) external;

    /// @dev push the input bool value to the existing bool array
    /// @param _key the key of the bool array
    /// @param _value the value to push to the existing bool array
    function pushBoolArray(bytes32 _key, bool _value) external;

    /// @dev set a specific index of the bool array with the input value
    /// @param _key the key of the bool array
    /// @param _index the index of the bool array to set
    /// @param _value the value to set
    function setBoolArrayAt(bytes32 _key, uint256 _index, bool _value) external;

    /// @dev set the string array for the given key
    /// @param _key the key of the string array
    /// @param _value the value of the string array
    function setStringArray(bytes32 _key, string[] memory _value) external;

    /// @dev push the input string value to the existing string array
    /// @param _key the key of the string array
    /// @param _value the value to push to the existing string array
    function pushStringArray(bytes32 _key, string memory _value) external;

    /// @dev set a specific index of the string array with the input value
    /// @param _key the key of the string array
    /// @param _index the index of the string array to set
    /// @param _value the value to set
    function setStringArrayAt(bytes32 _key, uint256 _index, string memory _value) external;

    /// @dev set the bytes32 array for the given key
    /// @param _key the key of the bytes32 array
    /// @param _value the value of the bytes32 array
    function setBytes32Array(bytes32 _key, bytes32[] memory _value) external;

    /// @dev push the input bytes32 value to the existing bytes32 array
    /// @param _key the key of the bytes32 array
    /// @param _value the value to push to the existing bytes32 array
    function pushBytes32Array(bytes32 _key, bytes32 _value) external;

    /// @dev set a specific index of the bytes32 array with the input value
    /// @param _key the key of the bytes32 array
    /// @param _index the index of the bytes32 array to set
    /// @param _value the value to set
    function setBytes32ArrayAt(bytes32 _key, uint256 _index, bytes32 _value) external;

    /// @dev add the given value to the set
    /// @param _setKey the key of the set
    /// @param _value the value to add
    function addAddress(bytes32 _setKey, address _value) external;

    /// @dev add a key-value pair to a map, or updates the value for an existing key returns true 
    ///      if the key was added to the map, that is if it was not already present
    /// @param _mapKey the key of the map
    /// @param _key the key to add
    /// @param _value the value to add
    function addAddressToUint(bytes32 _mapKey, address _key, uint256 _value) external returns (bool _added);

    // ============================================================================================
    // Removers
    // ============================================================================================

    /// @dev delete the uint value for the given key
    /// @param _key the key of the value
    function removeUint(bytes32 _key) external;

    function removeInt(bytes32 _key) external;

    /// @dev delete the address value for the given key
    /// @param _key the key of the value
    function removeAddress(bytes32 _key) external;

    /// @dev delete the bool value for the given key
    /// @param _key the key of the value
    function removeBool(bytes32 _key) external;

    /// @dev delete the string value for the given key
    /// @param _key the key of the value
    function removeString(bytes32 _key) external;

    /// @dev delete the bytes32 value for the given key
    /// @param _key the key of the value
    function removeBytes32(bytes32 _key) external;

    /// @dev delete the uint array for the given key
    /// @param _key the key of the uint array
    function removeUintArray(bytes32 _key) external;

    /// @dev delete the int array for the given key
    /// @param _key the key of the int array
    function removeIntArray(bytes32 _key) external;

    /// @dev delete the address array for the given key
    /// @param _key the key of the address array
    function removeAddressArray(bytes32 _key) external;

    /// @dev delete the bool array for the given key
    /// @param _key the key of the bool array
    function removeBoolArray(bytes32 _key) external;

    /// @dev delete the string array for the given key
    /// @param _key the key of the string array
    function removeStringArray(bytes32 _key) external;

    /// @dev delete the bytes32 array for the given key
    /// @param _key the key of the bytes32 array
    function removeBytes32Array(bytes32 _key) external;

    /// @dev remove the given value from the set
    /// @param _setKey the key of the set
    /// @param _value the value to remove
    function removeAddress(bytes32 _setKey, address _value) external;

    /// @dev removes a value from a set
    ///      returns true if the key was removed from the map, that is if it was present
    /// @param _mapKey the key of the map
    /// @param _key the key to remove
    /// @param _removed whether or not the key was removed
    function removeUintToAddress(bytes32 _mapKey, address _key) external returns (bool _removed);

    // ============================================================================================
    // Events
    // ============================================================================================

    event UpdateOwnership(address owner, bool isActive);

    // ============================================================================================
    // Errors
    // ============================================================================================

    error Unauthorized();
}
