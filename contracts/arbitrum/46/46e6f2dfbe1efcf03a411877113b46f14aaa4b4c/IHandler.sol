// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IHandler {
  function _resourceIDToTokenContractAddress(bytes32) external view returns (address);
}

