// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract AutismRegistrar {
    mapping(address => uint) public nonces;

    event RecordUpdatedFor(address indexed account, bytes value, bytes proof, address relayer);

    function updateFor(address account, bytes calldata value, bytes calldata proof) public {
        uint nonce = nonces[account];
        bytes32 msgHash = keccak256(abi.encodePacked(account, value, nonce));
        bytes32 signedMsgHash = getEthSignedMessageHash(msgHash);

        require(recoverSigner(signedMsgHash, proof) == account);

        nonces[account] = nonce + 1;

        emit RecordUpdatedFor(account, value, proof, msg.sender);
    }

    function recoverSigner(bytes32 msgHash, bytes memory proof) public pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(proof);
        return ecrecover(msgHash, v, r, s);
    }

    function splitSignature(bytes memory sig) public pure returns (
        bytes32 r,
        bytes32 s,
        uint8 v
    ) {
        require(sig.length == 65, "invalid signature length");

        assembly {
        /*
        First 32 bytes stores the length of the signature

        add(sig, 32) = pointer of sig + 32
        effectively, skips first 32 bytes of signature

        mload(p) loads next 32 bytes starting at the memory address p into memory
        */

        // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
        // second 32 bytes
            s := mload(add(sig, 64))
        // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        // implicitly return (r, s, v)
    }

    function getEthSignedMessageHash(bytes32 _messageHash) public pure returns (bytes32){
        return
        keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash)
        );
    }
}