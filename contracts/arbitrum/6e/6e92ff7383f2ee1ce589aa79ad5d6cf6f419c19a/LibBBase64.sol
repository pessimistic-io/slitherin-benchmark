// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title BBase64
/// @author Brecht Devos - <brecht@loopring.org>
/// @notice Provides a function for encoding some bytes in BBase64
library LibBBase64 {
    string internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function encode(bytes memory _data) internal pure returns (string memory) {
        if (_data.length == 0) return "";

        // load the _table into memory
        string memory _table = TABLE;

        // multiply by 4/3 rounded up
        uint256 _encodedLen = 4 * ((_data.length + 2) / 3);

        // add some extra buffer at the end required for the writing
        string memory _result = new string(_encodedLen + 32);

        assembly {
            // set the actual output length
            mstore(_result, _encodedLen)

            // prepare the lookup _table
            let tablePtr := add(_table, 1)

            // input ptr
            let dataPtr := _data
            let endPtr := add(dataPtr, mload(_data))

            // _result ptr, jump over length
            let resultPtr := add(_result, 32)

            // run over the input, 3 bytes at a time
            for { } lt(dataPtr, endPtr) { } {
                dataPtr := add(dataPtr, 3)

                // read 3 bytes
                let input := mload(dataPtr)

                // write 4 characters
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(18, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(12, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(6, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(input, 0x3F)))))
                resultPtr := add(resultPtr, 1)
            }

            // padding with '='
            switch mod(mload(_data), 3)
            case 1 { mstore(sub(resultPtr, 2), shl(240, 0x3d3d)) }
            case 2 { mstore(sub(resultPtr, 1), shl(248, 0x3d)) }
        }

        return _result;
    }
}

