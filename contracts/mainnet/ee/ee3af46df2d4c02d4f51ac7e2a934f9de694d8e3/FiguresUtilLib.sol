// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

library FiguresUtilLib {
    struct FigStrings {
        string[] s1;
        string[] s2;
    }

    function substring(
        string memory str,
        uint256 startIndex,
        uint256 endIndex
    ) public pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    function _assignValuesSingle(string memory input, uint16 size)
        internal
        pure
        returns (string[] memory)
    {
        return _assignValues(input, size, 50);
    }

    function _assignValuesDouble(string memory input, uint16 size)
        internal
        pure
        returns (string[] memory)
    {
        return _assignValues(input, size, 25);
    }

    function _assignValues(
        string memory input,
        uint16 size,
        uint8 length
    ) internal pure returns (string[] memory) {
        string[] memory output = new string[](size);
        for (uint256 i = 0; i < size; i++) {
            output[i] = substring(input, i * length, i * length + length);
        }
        return output;
    }

    function _chooseStringsSingle(
        uint8 number,
        string[] memory strings1,
        string[] memory strings2,
        uint8 index1,
        uint8 index2
    ) internal pure returns (bool[][2] memory b) {
        return _chooseStrings(number, strings1, strings2, index1, index2, 50);
    }

    function _chooseStringsDouble(
        uint8 number,
        string[] memory strings1,
        string[] memory strings2,
        uint8 index1,
        uint8 index2
    ) internal pure returns (bool[][2] memory b) {
        return _chooseStrings(number, strings1, strings2, index1, index2, 25);
    }

    function _chooseStrings(
        uint8 number,
        string[] memory strings1,
        string[] memory strings2,
        uint8 index1,
        uint8 index2,
        uint8 length
    ) private pure returns (bool[][2] memory b) {
        string[2] memory s;
        // some arrays are shorter than the random number generated
        uint256 availableIndex1 = index1 % strings1.length;
        uint256 availableIndex2 = index2 % strings2.length;
        s[0] = strings1[availableIndex1];
        s[1] = strings2[availableIndex2];

        // Special cases for 0, 1, 7
        if (number == 0 || number == 1 || number == 7) {
            if (length == 25) {
                while (
                    keccak256(bytes(substring(s[0], 20, 24))) !=
                    keccak256(bytes(substring(s[1], 0, 4)))
                ) {
                    uint256 is2 = ((availableIndex2 + availableIndex1++) %
                        strings2.length);
                    s[1] = strings2[is2];
                }
            }
            if (length == 50) {
                while (
                    keccak256(bytes(substring(s[0], 40, 49))) !=
                    keccak256(bytes(substring(s[1], 0, 9)))
                ) {
                    uint256 is2 = ((availableIndex2 + availableIndex1++) %
                        strings2.length);
                    s[1] = strings2[is2];
                }
            }
        }

        b[0] = _returnBoolArray(s[0]);
        b[1] = _returnBoolArray(s[1]);

        return b;
    }

    function checkString(string memory s1, string memory s2) private pure {}

    function _returnBoolArray(string memory s)
        internal
        pure
        returns (bool[] memory)
    {
        bytes memory b = bytes(s);
        bool[] memory a = new bool[](b.length);
        for (uint256 i = 0; i < b.length; i++) {
            uint8 z = (uint8(b[i]));
            if (z == 48) {
                a[i] = true;
            } else if (z == 49) {
                a[i] = false;
            }
        }
        return a;
    }
}

