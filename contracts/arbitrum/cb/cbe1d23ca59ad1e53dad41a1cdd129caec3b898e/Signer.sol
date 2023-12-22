// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./IAccessToken.sol";

contract Signer {
    function getEthSignedMessageHash(
        uint256 accessKey,
        uint256 chainid,
        address contractAddress,
        uint256 nonce
    ) internal pure returns (bytes32) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(accessKey, chainid, contractAddress, nonce)
        );
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    messageHash
                )
            );
    }

    function recoverSigner(
        bytes32 ethSignedMessageHash,
        SignatureData memory signatureData
    ) internal pure returns (address) {
        return
            ecrecover(
                ethSignedMessageHash,
                signatureData.v,
                signatureData.r,
                signatureData.s
            );
    }
}

