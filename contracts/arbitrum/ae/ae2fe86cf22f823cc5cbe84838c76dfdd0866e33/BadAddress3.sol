// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract BadAddress3 {
    // no receive or fallback function

    function hello() public returns (bool) {
        return true;
    }
}
