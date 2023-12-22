// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


contract BlockNumber {

    function blockNumber() public view returns (uint256) {
        return block.number;
    }

}