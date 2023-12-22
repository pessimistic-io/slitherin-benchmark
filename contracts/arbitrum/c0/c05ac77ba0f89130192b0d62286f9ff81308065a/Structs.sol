// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface CATERC721Structs {
    struct CrossChainPayload {
        // Address of the token. Left-zero-padded if shorter than 32 bytes
        bytes32 tokenAddress;
        // Chain ID of the token
        uint16 tokenChain;
        // TokenID of the token
        uint256 tokenID;
        // URI of the token metadata (UTF-8)
        string uri;
        // Address of the recipient. Left-zero-padded if shorter than 32 bytes
        bytes32 toAddress;
        // Chain ID of the recipient
        uint16 toChain;
    }

    struct SignatureVerification {
        // Address of custodian the user has delegated to sign transaction on behalf of
        address custodian;
        // Timestamp the transaction will be valid till
        uint256 validTill;
        // Signed Signature
        bytes signature;
    }
}

