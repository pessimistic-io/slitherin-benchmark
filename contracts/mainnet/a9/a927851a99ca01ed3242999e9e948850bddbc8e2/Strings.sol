// SPDX-License-Identifier: Unlicense
// OpenZeppelin Contracts v4.4.0 (utils/Strings.sol) - MODIFIED
pragma solidity ^0.8.0;

library Strings {
    function toString(uint256 _value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol
        if (_value == 0) {
            return "0";
        }

        uint256 temp = _value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (_value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(_value % 10)));
            _value /= 10;
        }

        return string(buffer);
    }

    // Source: https://ethereum.stackexchange.com/questions/8346/convert-address-to-string (MODIFIED)
    function toString(address _addr) internal pure returns (string memory) {
        bytes memory buffer = new bytes(40);
        for (uint8 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(_addr)) / (2**(8 * (19 - i)))));
            bytes1 high = bytes1(uint8(b) / 16);
            bytes1 low = bytes1(uint8(b) - 16 * uint8(high));
            buffer[2 * i] = char(high);
            buffer[2 * i + 1] = char(low);
        }

        return string(abi.encodePacked("0x", string(buffer)));
    }

    function char(bytes1 _byte) internal pure returns (bytes1) {
        if (uint8(_byte) < 10) {
            return bytes1(uint8(_byte) + 0x30);
        } else {
            return bytes1(uint8(_byte) + 0x57);
        }
    }

    function truncateAddressString(string memory _str) internal pure returns (string memory) {
        bytes memory b = bytes(_str);
        return
            string(
                abi.encodePacked(
                    string(abi.encodePacked(b[0], b[1], b[2], b[3], b[4], b[5])),
                    "...",
                    string(abi.encodePacked(b[36], b[37], b[38], b[39], b[40], b[41]))
                )
            );
    }

    function equal(string memory _a, string memory _b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
    }
}

