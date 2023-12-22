// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

contract FCCTask {
    uint256 public s_variable = 0;
    uint256 public s_otherVar = 0;

    function doSomething() public {
        s_variable = 123;
    }

    function doSomethingElse() public {
        s_otherVar = s_otherVar + 1;
    }

    function getSelector() public pure returns (bytes4 selector) {
        selector = bytes4(keccak256(bytes("doSomethingElse()")));
    }
}