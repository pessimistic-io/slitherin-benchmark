// SPDX-License-Identifier: MIT
// Metaline Contracts (Crypto.sol)

pragma solidity ^0.8.0;

import "./ECDSA.sol";

library Crypto {
    using ECDSA for bytes32;
    
    function verifySignature(bytes memory data, bytes memory signature, address account) external pure returns (bool) {
        return keccak256(data)
            .toEthSignedMessageHash()
            .recover(signature) == account;
    }
}
