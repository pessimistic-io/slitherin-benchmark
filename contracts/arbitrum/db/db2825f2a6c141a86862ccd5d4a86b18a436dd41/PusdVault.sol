//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import { BaseIRVault } from "./BaseIrVault.sol";

/// @title Pusd Interest Rate Vault
contract PusdVault is BaseIRVault {
  constructor(Addresses memory _addresses) BaseIRVault(_addresses) {}
}

