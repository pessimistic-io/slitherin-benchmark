// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract BadAddress {

    receive() external payable {
        revert("Cannot accept ether");
    }

}
