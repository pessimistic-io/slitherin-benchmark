// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

abstract contract Signature {
    /**
     * @dev Returns the address that signed a message given a signature.
     * @param message The message signed.
     * @param signature The signature.
     */
    function getSignatureAddress(bytes32 message, bytes memory signature)
        internal
        pure
        returns (address)
    {
        assert(signature.length == 65);
        uint8 v;
        bytes32 r;
        bytes32 s;
        assembly {
            // First 32 bytes after length prefix.
            r := mload(add(signature, 32))
            // Next 32 bytes.
            s := mload(add(signature, 64))
            // Final byte.
            v := byte(0, mload(add(signature, 96)))
        }
        return ecrecover(message, v, r, s);
    }

    function encodeERC191(bytes32 message) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    bytes1(0x19),
                    bytes1("E"),
                    bytes("thereum Signed Message:\n32"),
                    abi.encodePacked(message)
                )
            );
    }
}

