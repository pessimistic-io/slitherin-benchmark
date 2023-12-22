// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

/**
 * @dev Attempted to call contract without being linked vault
 */
error NotLinkedVault();

/**
 * @dev Attempted to set another linked vault after the first time
 */
error CannotSetAnotherLinkedVault();

