// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

library VaultErrors {
    string public constant CALLER_NOT_VAULT_ADMIN = "CALLER_IS_NOT_VAULT_ADMIN";
    string public constant CALLER_NOT_VAULT_ADMIN_OR_OPERATIONS = "CALLER_IS_NOT_VAULT_ADMIN_OR_OPERATIONS";
    string public constant ADDRESS_IS_ZERO = "ADDRESS_IS_ZERO";
    string public constant CALLER_NOT_ACCESS_ADMIN = "CALLER_NOT_ACCESS_ADMIN";
    string public constant INVALID_VIT_WEIGHTS = "INVALID_VIT_WEIGHTS";
    string public constant BATCH_REDEEM_DISABLED = "BATCH_REDEEM_DISABLED";
}
