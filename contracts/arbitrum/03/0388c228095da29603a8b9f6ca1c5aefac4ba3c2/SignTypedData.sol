// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ECDSA.sol";

contract SignTypedData {
    bytes32 private DOMAIN_TYPEHASH;

    constructor(string memory domainName_, string memory domainVersion_) {
        DOMAIN_TYPEHASH = keccak256(abi.encode(domainName_, domainVersion_));
    }

    function _recoverSigner(
        bytes32 dataHash,
        bytes memory signature
    ) internal view returns (address) {
        bytes32 _hash = keccak256(abi.encodePacked(DOMAIN_TYPEHASH, dataHash));
        bytes32 messageHash = ECDSA.toEthSignedMessageHash(_hash);
        return ECDSA.recover(messageHash, signature);
    }
}

