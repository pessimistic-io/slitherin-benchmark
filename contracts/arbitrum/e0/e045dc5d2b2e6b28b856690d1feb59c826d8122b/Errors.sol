// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Errors {
  string public constant INVALID_INPUT = "00";
  string public constant NON_AUTH = "01";
  string public constant NONEXISTENCE = "02";
  string public constant ILLEGAL_STATE = "03";
  string public constant EXCEEDS = "04";
  string public constant NOT_OWNER = "05";
  string public constant INSUFFICIENT_BALANCE = "06";
  string public constant FAILED = "99";
}
