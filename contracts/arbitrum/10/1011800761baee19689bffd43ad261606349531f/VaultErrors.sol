// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

/**
 * @title library for Vault Errors mapping
 * @author Souq.Finance
 * @notice Defines the output of vault error messages reverted by the contracts of the Souq protocol
 * @notice License: https://souq-etf.s3.amazonaws.com/LICENSE.md
 */

library VaultErrors {
    string public constant CALLER_IS_NOT_VAULT_ADMIN = "CALLER_IS_NOT_VAULT_ADMIN";
    string public constant CALLER_IS_NOT_VAULT_ADMIN_OR_OPERATIONS = "CALLER_IS_NOT_VAULT_ADMIN_OR_OPERATIONS";
    string public constant CALLER_NOT_UPGRADER = "CALLER_NOT_UPGRADER";
    string public constant CALLER_NOT_DEPLOYER = "CALLER_NOT_DEPLOYER";
    string public constant CALLER_NOT_REWEIGHTER = "CALLER_NOT_REWEIGHTER";
    string public constant ADDRESS_IS_ZERO = "ADDRESS_IS_ZERO";
    string public constant VALUE_IS_ZERO = "VALUE_IS_ZERO";
    string public constant CALLER_NOT_ACCESS_ADMIN = "CALLER_NOT_ACCESS_ADMIN";
    string public constant INVALID_VIT_WEIGHTS = "INVALID_VIT_WEIGHTS";
    string public constant BATCH_REDEEM_DISABLED = "BATCH_REDEEM_DISABLED";
    string public constant ARRAY_NOT_SAME_LENGTH = "ARRAY_NOT_SAME_LENGTH";
    string public constant ONLY_OWNER_CAN_WITHDRAW_DUST = "ONLY_OWNER_CAN_WITHDRAW_DUST";
    string public constant ONLY_VAULT = "ONLY_VAULT";
}

