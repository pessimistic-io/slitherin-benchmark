// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library StorageWriter {
  // *** Setter Methods ***
  function setUint(
    address storageAddr,
    bytes32 key,
    uint256 value
  ) internal {
    (bool success, bytes memory returnData) = storageAddr.delegatecall(abi.encodeWithSignature('setUint(bytes32,uint256)', key, value));
    require(success, string(returnData));
  }

  function setString(
    address storageAddr,
    bytes32 key,
    string memory value
  ) internal {
    (bool success, bytes memory returnData) = storageAddr.delegatecall(
      abi.encodeWithSignature('setString(bytes32,string memory)', key, value)
    );
    require(success, string(returnData));
  }

  function setAddress(
    address storageAddr,
    bytes32 key,
    address value
  ) internal {
    (bool success, bytes memory returnData) = storageAddr.delegatecall(abi.encodeWithSignature('setAddress(bytes32,address)', key, value));
    require(success, string(returnData));
  }

  function setBytes(
    address storageAddr,
    bytes32 key,
    bytes memory value
  ) internal {
    (bool success, bytes memory returnData) = storageAddr.delegatecall(
      abi.encodeWithSignature('setBytes(bytes32,bytes memory)', key, value)
    );
    require(success, string(returnData));
  }

  function setBool(
    address storageAddr,
    bytes32 key,
    bool value
  ) internal {
    (bool success, bytes memory returnData) = storageAddr.delegatecall(abi.encodeWithSignature('setBool(bytes32,bool)', key, value));
    require(success, string(returnData));
  }

  function setInt(
    address storageAddr,
    bytes32 key,
    int256 value
  ) internal {
    (bool success, bytes memory returnData) = storageAddr.delegatecall(abi.encodeWithSignature('setInt(bytes32,int256)', key, value));
    require(success, string(returnData));
  }

  // *** Delete Methods ***
  function deleteUint(address storageAddr, bytes32 key) internal {
    (bool success, bytes memory returnData) = storageAddr.delegatecall(abi.encodeWithSignature('deleteUint(bytes32,string memory)', key));
    require(success, string(returnData));
  }

  function deleteString(address storageAddr, bytes32 key) internal {
    (bool success, bytes memory returnData) = storageAddr.delegatecall(abi.encodeWithSignature('setString(bytes32,string memory)', key));
    require(success, string(returnData));
  }

  function deleteAddress(address storageAddr, bytes32 key) internal {
    (bool success, bytes memory returnData) = storageAddr.delegatecall(abi.encodeWithSignature('setString(bytes32,string memory)', key));
    require(success, string(returnData));
  }

  function deleteBytes(address storageAddr, bytes32 key) internal {
    (bool success, bytes memory returnData) = storageAddr.delegatecall(abi.encodeWithSignature('setString(bytes32,string memory)', key));
    require(success, string(returnData));
  }

  function deleteBool(address storageAddr, bytes32 key) internal {
    (bool success, bytes memory returnData) = storageAddr.delegatecall(abi.encodeWithSignature('setString(bytes32,string memory)', key));
    require(success, string(returnData));
  }

  function deleteInt(address storageAddr, bytes32 key) internal {
    (bool success, bytes memory returnData) = storageAddr.delegatecall(abi.encodeWithSignature('setString(bytes32,string memory)', key));
    require(success, string(returnData));
  }

  function setActionAddress(
    address storageAddr,
    uint16 actionId,
    address actionAddress
  ) internal {
    (bool success, bytes memory returnData) = storageAddr.delegatecall(
      abi.encodeWithSignature('setActionAddress(uint16,address)', actionId, actionAddress)
    );
    require(success, string(returnData));
  }
}

