// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

contract Counter {

    uint256 public count;

    constructor() {
      count = 0;
    }

    function increment() public {
        count += 1;
    }
}
