// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./ISignedNftStorage.sol";

abstract contract Sign is ISignedNftStorage {
    error UnconfirmedSignature();
    error ExternalIdAlreadyUsed(uint64 externalId);
    error ExpiredSignature(uint64 expiredAt, uint64 currentTimestamp);

    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function _verifySignature(
            address lootBoxAddress,
            address userAddress,
            uint64 externalId,
            uint64 expiredAt,
            Signature calldata signature) internal view {
        // check if signature expired
        uint64 currentTimestamp = uint64(block.timestamp);
        if (currentTimestamp > expiredAt) {
            revert ExpiredSignature(expiredAt, currentTimestamp);
        }

        bytes memory encoded = abi.encodePacked(lootBoxAddress, userAddress, externalId, expiredAt);
        bytes32 hash = sha256(encoded);

        address recoveredSigner = ecrecover(hash, signature.v, signature.r, signature.s);

        if (_signer() != recoveredSigner) {
            revert UnconfirmedSignature();
        }
    }

    function _verifySignature(address lootBoxAddress, address userAddress, uint64 expiredAt, Signature calldata signature) internal view {
        // check if signature expired
        uint64 currentTimestamp = uint64(block.timestamp);
        if (currentTimestamp > expiredAt) {
            revert ExpiredSignature(expiredAt, currentTimestamp);
        }

        bytes memory encoded = abi.encodePacked(lootBoxAddress, userAddress, expiredAt);
        bytes32 hash = sha256(encoded);

        address recoveredSigner = ecrecover(hash, signature.v, signature.r, signature.s);

        if (_signer() != recoveredSigner) {
            revert UnconfirmedSignature();
        }
    }
}

