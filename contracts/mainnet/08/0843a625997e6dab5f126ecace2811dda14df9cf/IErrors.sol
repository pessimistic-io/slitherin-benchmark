// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

error PayeeSharesArrayMismatch(uint256 payeesLength, uint256 sharesLength);
error PayeeAlreadyExists(address payee);
error InvalidTotalShares(uint256 totalShares);

