// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract Greeting {
  function greet(string calldata name) external pure returns (string memory) {
    return string.concat("Hello, ", name, "!");
  }
}