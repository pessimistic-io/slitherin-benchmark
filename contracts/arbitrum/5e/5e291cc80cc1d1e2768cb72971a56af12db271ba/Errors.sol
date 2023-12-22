// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

/**
 * @dev Action restricted. Given account is not allowed to run it
 */
error Restricted();

/**
 * @dev Trying to set Zero Address to an attribute that cannot be 0
 */
error ZeroAddress();

/**
 * @dev Attribute already set and does not allow resetting
 */
error AlreadySet();

/**
 * @dev A cap has been exceeded - temporarily locked
 */
error CapExceeded();

/**
 * @dev A deadline has been wrongly set
 */
error WrongDeadline();

/**
 * @dev A kill switch is in play. Action restricted and temporarily frozen
 */
error KillSwitch();

/**
 * @dev A value cannot be zero
 */
error ZeroValue();

/**
 * @dev Value exceeded maximum allowed
 */
error TooBig();

/**
 * @dev Appointed item does not exist
 */
error NotExists();

/**
 * @dev Appointed item already exist
 */
error AlreadyExists();

/**
 * @dev Timed action has timed out
 */
error Timeout();

/**
 * @dev Insufficient funds to perform action
 */
error InsufficientFunds();

/**
 * @dev Wrong currency used
 */
error WrongCurrency();

/**
 * @dev Blocked action. For timing or other reasons
 */
error Blocked();

/**
 * @dev Suspended access
 */
error Suspended();

/**
 * @dev Nothing to claim
 */
error NothingToClaim();

/**
 * @dev Missing vesting tokens
 */
error MissingVestingTokens();

