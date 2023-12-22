// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.20;

/// @dev Represents the ERC20 token amount.
type Amount is uint256;
using {add as +, sub as -, isZero} for Amount global;

function add(Amount a, Amount b) pure returns (Amount sum) {
    sum = Amount.wrap(Amount.unwrap(a) + Amount.unwrap(b));
}

function sub(Amount a, Amount b) pure returns (Amount difference) {
    difference = Amount.wrap(Amount.unwrap(a) - Amount.unwrap(b));
}

function isZero(Amount a) pure returns (bool result) {
    result = Amount.unwrap(a) == 0;
}
