// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract HashGenerator {
    function generatePositionKey(int24 tickLower, int24 tickUpper) public view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
    }
}