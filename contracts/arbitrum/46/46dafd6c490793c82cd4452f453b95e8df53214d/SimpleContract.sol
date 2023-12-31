// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SimpleContract {
    uint256 public value;

    function updateValue(uint256 newValue) public {
        require(newValue != value, "Value must be different");

        value = newValue;
    }
}