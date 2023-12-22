// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract Four {
    uint256 public count;

    function increment() public returns (bool) {
        require(gasleft() >= 30000, "Insufficient gas");
        count++;
        return true;
    }
}
