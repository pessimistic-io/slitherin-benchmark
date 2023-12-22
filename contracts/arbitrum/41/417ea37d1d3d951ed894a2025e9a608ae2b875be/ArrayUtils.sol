// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library MemoryArrayUtilsForAddress {
    function reverse(address[] memory input)
        internal
        pure
        returns (address[] memory)
    {
        address[] memory output = new address[](input.length);
        for (uint256 i = 0; i < input.length; i++) {
            output[i] = input[input.length - 1 - i];
        }
        return output;
    }

    function indexOf(address[] memory input, address value)
        internal
        pure
        returns (uint256)
    {
        for (uint256 i = 0; i < input.length; i++) {
            if (input[i] == value) {
                return i;
            }
        }
        return input.length;
    }
}

