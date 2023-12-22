// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract BlockNum {
    function getBlockNumber() external view returns (uint256) {
        return block.number;
    }
}