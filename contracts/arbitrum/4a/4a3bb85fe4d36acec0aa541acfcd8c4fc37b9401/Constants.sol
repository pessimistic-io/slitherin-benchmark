// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

// Basic contract to hold some constants used throughout the Taurus system
library Constants {
    // Roles
    // Role for keepers, trusted accounts which manage system operations.
    bytes32 internal constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    // Role for the team multisig, which adds/removes keepers and may perform other administrative functions in the future.
    bytes32 internal constant MULTISIG_ROLE = keccak256("MULTISIG_ROLE");

    // Governance has DEFAULT_ADMIN_ROLE i.e. bytes32(0). This puts it in charge of the multisig as well. It's exposed here for convenience.
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);

    // SwapAdapter names
    bytes32 internal constant UNISWAP_SWAP_ADAPTER = keccak256("UNISWAP_SWAP_ADAPTER");
    bytes32 internal constant CURVE_SWAP_ADAPTER = keccak256("CURVE_SWAP_ADAPTER");

    // Role for accounts that can liquidate the underwater accounts in the system
    bytes32 internal constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    // Addresses given the vault role are authorized to perform swaps through swap adapters.
    bytes32 internal constant VAULT_ROLE = keccak256("VAULT_ROLE");

    uint256 internal constant PRECISION = 1e18;

    // Fees

    uint256 internal constant MAX_FEE_PERC = 4e17; // Max protocol fees are 40%
    uint256 internal constant PERCENT_PRECISION = 1e18; // i.e. 1% will be represented as 1e16.

    // Fee names
    // Key used by the FeeMapper to store the protocol fee for each vault. The protocol fee is charged on vault yield and is sent to the FeeSplitter
    // It uses 18 decimals, so 1e16 would be 1%.
    bytes32 internal constant VAULT_PROTOCOL_FEE_KEY = keccak256("VAULT_PROTOCOL_FEE");

    bytes32 internal constant TAURUS_LIQUIDATION_FEE_KEY = keccak256("TAURUS_LIQUIDATION_FEE");

    bytes32 internal constant PRICE_ORACLE_MANAGER = keccak256("PRICE_ORACLE_MANAGER");

    bytes32 internal constant FEE_SPLITTER = keccak256("FEE_SPLITTER");
}

