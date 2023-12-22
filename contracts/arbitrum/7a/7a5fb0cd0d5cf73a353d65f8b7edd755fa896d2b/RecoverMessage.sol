// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract RecoverMessage {

    // This is the EIP-2098 compact representation, which reduces gas costs
    struct SignatureCompact {
        bytes32 r;
        bytes32 yParityAndS;
    }

    // This is an expaned Signature representation
    struct SignatureExpanded {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function itoa(uint value) private pure returns (string memory) {

        // Count the length of the decimal string representation
        uint length = 1;
        uint v = value;
        while ((v /= 10) != 0) { length++; }

        // Allocated enough bytes
        bytes memory result = new bytes(length);

        // Place each ASCII string character in the string,
        // right to left
        while (true) {
            length--;

            // The ASCII value of the modulo 10 value
            result[length] = bytes1(uint8(0x30 + (value % 10)));

            value /= 10;

            if (length == 0) { break; }
        }

        return string(result);
    }

    // Helper function
    function _ecrecover(string memory message, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        // Compute the EIP-191 prefixed message
        bytes memory prefixedMessage = abi.encodePacked(
            "\x19Ethereum Signed Message:\n",
            itoa(bytes(message).length),
            message
        );

        // Compute the message digest
        bytes32 digest = keccak256(prefixedMessage);

        // Use the native ecrecover provided by the EVM
        return ecrecover(digest, v, r, s);
    }

    // Recover the address from a raw signature. The signature is 65 bytes, which when
    // ABI encoded is 160 bytes long (a pointer, a length and the padded 3 words of data).
    //
    // When using raw signatures, some tools return the v as 0 or 1. In this case you must
    // add 27 to that value as v must be either 27 or 28.
    //
    // This Signature format is 65 bytes of data, but when ABI encoded is 160 bytes in length;
    // a pointer (32 bytes), a length (32 bytes) and the padded 3 words of data (96 bytes).
    function recoverStringFromRaw(string calldata message, bytes calldata sig) public pure returns (address) {

        // Sanity check before using assembly
        require(sig.length == 65, "invalid signature");

        // Decompose the raw signature into r, s and v (note the order)
        uint8 v;
        bytes32 r;
        bytes32 s;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 0x20))
            v := calldataload(add(sig.offset, 0x21))
        }

        return _ecrecover(message, v, r, s);
    }

    // This is provided as a quick example for those that only need to recover a signature
    // for a signed hash (highly discouraged; but common), which means we can hardcode the
    // length in the prefix. This means we can drop the itoa and _ecrecover functions above.
    function recoverHashFromCompact(bytes32 hash, SignatureCompact calldata sig) public pure returns (address) {
        bytes memory prefixedMessage = abi.encodePacked(
        // Notice the length of the message is hard-coded to 32
        // here -----------------------v
            "\x19Ethereum Signed Message:\n32",
            hash
        );

        bytes32 digest = keccak256(prefixedMessage);

        // Decompose the EIP-2098 signature
        uint8 v = 27 + uint8(uint256(sig.yParityAndS) >> 255);
        bytes32 s = bytes32((uint256(sig.yParityAndS) << 1) >> 1);

        return ecrecover(digest, v, sig.r, s);
    }

    function addressToString(address _addr) public pure returns(string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2+i*2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3+i*2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    function uint256ToString(uint256 _value) public pure returns(string memory) {
        // Simple implementation (or use OpenZeppelin's toString library)
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
            buffer[digits] = bytes1(uint8(48 + _value % 10));
            _value /= 10;
        }
        return string(buffer);
    }

    function concatAddressAndString(address _addr, string memory _value) public pure returns (string memory) {
        return string(abi.encodePacked(addressToString(_addr), _value));
    }
}
