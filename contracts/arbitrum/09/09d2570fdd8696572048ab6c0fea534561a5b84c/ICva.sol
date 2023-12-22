// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface ICva {
  function approveAndDeposit(
    address, // ERC20
    uint8, // destinationDomainID
    bytes32, // resourceID
    bytes calldata, // depositData
    bytes calldata // feeData
  ) external;

  function deposit(
    uint8, // destinationDomainID
    bytes32, // resourceID
    bytes calldata, // depositData
    bytes calldata // feeData
  ) external;
}

