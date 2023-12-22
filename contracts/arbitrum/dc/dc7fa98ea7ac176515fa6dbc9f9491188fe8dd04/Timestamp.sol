// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.20;

/// @dev Represents the number of seconds in unix timestamp.
type Timestamp is uint256;
using {add as +, sub as -, equal as ==, notEqual as !=, lessThan as <, lessThanOrEqual as <=, greaterThan as >, greaterThanOrEqual as >=} for Timestamp global;

function add(Timestamp a, Timestamp b) pure returns (Timestamp sum) {
    sum = Timestamp.wrap(Timestamp.unwrap(a) + Timestamp.unwrap(b));
}

function sub(Timestamp a, Timestamp b) pure returns (Timestamp difference) {
    difference = Timestamp.wrap(Timestamp.unwrap(a) - Timestamp.unwrap(b));
}

function equal(Timestamp a, Timestamp b) pure returns (bool result) {
    result = Timestamp.unwrap(a) == Timestamp.unwrap(b);
}

function notEqual(Timestamp a, Timestamp b) pure returns (bool result) {
    result = Timestamp.unwrap(a) != Timestamp.unwrap(b);
}

function lessThan(Timestamp a, Timestamp b) pure returns (bool result) {
    result = Timestamp.unwrap(a) < Timestamp.unwrap(b);
}

function lessThanOrEqual(Timestamp a, Timestamp b) pure returns (bool result) {
    result = Timestamp.unwrap(a) <= Timestamp.unwrap(b);
}

function greaterThan(Timestamp a, Timestamp b) pure returns (bool result) {
    result = Timestamp.unwrap(a) > Timestamp.unwrap(b);
}

function greaterThanOrEqual(Timestamp a, Timestamp b) pure returns (bool result) {
    result = Timestamp.unwrap(a) >= Timestamp.unwrap(b);
}
