// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
// https://solidity-by-example.org/signature/

function getEthSignedMessageWithPrefix(
    string memory _message
) pure returns (bytes32) {

    // 99 - length of prefix "Manage your redefined : Identity\n" and hash of message
    return keccak256(
        abi.encodePacked("\x19Ethereum Signed Message:\n99", "Manage your redefined : Identity\n", _message)
    );
}

function recoverSigner(
    bytes32 _ethSignedMessageHash,
    bytes memory _signature
) pure returns (address) {

    (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

    return ecrecover(_ethSignedMessageHash, v, r, s);
}

function splitSignature(
    bytes memory sig
) pure returns (bytes32 r, bytes32 s, uint8 v) {

    require(sig.length == 65, "invalid signature length");

    assembly {
        r := mload(add(sig, 32))
        s := mload(add(sig, 64))
        v := byte(0, mload(add(sig, 96)))
    }
}
