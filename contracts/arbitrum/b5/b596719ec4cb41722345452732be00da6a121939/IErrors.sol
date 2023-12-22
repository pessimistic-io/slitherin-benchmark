// SPDX-License-Identifier: BUSL-1.1

// (c) Gearbox Holdings, 2022

// This code was largely inspired by Gearbox Protocol

pragma solidity 0.8.18;

/// @dev Common contract exceptions

/// @dev Thrown on attempting to set an important address to zero address
error ZeroAddressException();

/// @dev Thrown on attempting to call a non-implemented function
error NotImplementedException();

/// @dev Thrown on attempting to set an EOA as an important contract in the system
error AddressIsNotContractException(address);

/// @dev Thrown on attempting to use a non-ERC20 contract or an EOA as a token
error IncorrectTokenContractException();

