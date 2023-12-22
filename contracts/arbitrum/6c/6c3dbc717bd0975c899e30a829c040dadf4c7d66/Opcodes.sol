/**
 * A bunch of simple functions, reimplementing native opcodes or solidity features
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract Opcodes {
    /**
     * self()
     * get own address
     * @return ownAddress
     */
    function self() public view returns (address ownAddress) {
        ownAddress = address(this);
    }

    /**
     * extractFirstWord()
     * Takes in a byte, extracts it's first 32 byte word
     */
    function extractFirstWord(
        bytes memory arg
    ) public pure returns (bytes32 firstWord) {
        assembly {
            firstWord := mload(add(arg, 0x20))
        }
    }

    /**
     * encodeWordAtIndex()
     * @param arg - The original arg to extract from
     * @param idx - The index of the word to extract (starts at 0 for first word)
     * @return extractedWord - 32 byte at the index
     */
    function extractWordAtIndex(
        bytes memory arg,
        uint256 idx
    ) public pure returns (bytes32 extractedWord) {
        assembly {
            extractedWord := mload(add(arg, add(0x20, mul(0x20, idx))))
        }
    }
}

