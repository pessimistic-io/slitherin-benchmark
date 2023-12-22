// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./StrictBank.sol";

// @title OrderVault
// @dev Vault for orders
contract OrderVault is StrictBank {
    constructor(RoleStore _roleStore, DataStore _dataStore) StrictBank(_roleStore, _dataStore) {}
}

