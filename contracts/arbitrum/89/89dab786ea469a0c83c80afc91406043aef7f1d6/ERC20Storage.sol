// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

/**
 * @title ERC20Storage
 * @author Tazz Labs
 * @notice Contract used as storage of the ERC20 contracts (both Asset and Liability Tokens).
 * @dev It defines the storage layout of the ERC20 contract.
 */
contract ERC20Storage {
    // Map of user balances
    mapping(address => uint256) internal _balances;

    // Map of allowances (delegator => delegatee => allowanceAmount)
    mapping(address => mapping(address => uint256)) internal _allowances;

    uint256 internal _totalSupply;
    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;
}

