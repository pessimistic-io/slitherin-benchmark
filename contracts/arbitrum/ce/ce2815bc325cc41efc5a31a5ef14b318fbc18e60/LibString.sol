// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;


/**
 * @title LibString
 * @author Deepp Dev Team
 * @notice Utility to efficiently compare strings when necessary.
 */
library LibString {

    /**
     * @notice Compares two strings by taking their hash.
     * @param a The first string.
     * @param b The second string.
     * @return bool true or false depending on the strings compared.
     */
    function equals(string memory a, string memory b)
        internal
        pure
        returns (bool)
    {
        return keccak256(abi.encode(a)) == keccak256(abi.encode(b));
    }
}

