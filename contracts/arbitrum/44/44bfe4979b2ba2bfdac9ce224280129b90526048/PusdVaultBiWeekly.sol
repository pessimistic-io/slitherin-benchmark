//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import { BaseIRVault } from "./BaseIrVault.sol";

contract PusdVaultWeekly is BaseIRVault {
  constructor(Addresses memory _addresses) BaseIRVault(_addresses) {}
}

