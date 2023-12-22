// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

library StringUtils {
    /**
     * @dev Returns the length of a given string
     *
     * @param s The string to measure the length of
     * @return The length of the input string
     */
    function strlen(string memory s) internal pure returns (uint256) {
        uint256 len;
        uint256 i = 0;
        uint256 bytelength = bytes(s).length;
        for (len = 0; i < bytelength; len++) {
            bytes1 b = bytes(s)[i];
            if (b < 0x80) {
                i += 1;
            } else if (b < 0xE0) {
                i += 2;
            } else if (b < 0xF0) {
                i += 3;
            } else if (b < 0xF8) {
                i += 4;
            } else if (b < 0xFC) {
                i += 5;
            } else {
                i += 6;
            }
        }
        return len;
    }

    function bytesToHexString(bytes memory bs) internal pure returns(string memory) {
        bytes memory tempBytes = new bytes(bs.length * 2);
        uint len = bs.length;
        for (uint i = 0; i < len; i++) {
            bytes1 b = bs[i];
            bytes1 nb = (b & 0xf0) >> 4;
            tempBytes[2 * i] = nb > 0x09 ? bytes1((uint8(nb) + 0x37)) : (nb | 0x30);
            nb = (b & 0x0f);
            tempBytes[2 * i + 1] = nb > 0x09 ? bytes1((uint8(nb) + 0x37)) : (nb | 0x30);
        }
        return string(tempBytes);
    }

    function bytesToString(bytes memory _bytes) internal pure returns (string memory) {
        uint256 length = _bytes.length;
        bytes memory str = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            str[i] = _bytes[i];
        }
        return string(str);
    }

    function bytes32ToHexString(bytes32 _bts32) internal pure
    returns (string memory)
    {
        bytes memory result = new bytes(_bts32.length);
        for (uint256 i = 0; i < _bts32.length; i++) {
            result[i] = _bts32[i];
        }

        return bytesToHexString(result);
    }
}

