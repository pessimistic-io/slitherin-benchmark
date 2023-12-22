// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

struct PetBonk {
    uint256 targetId;
    bytes32 nonce;
    bytes32 commit;
}

struct BonkStorage {
    address bonkSigner;
    mapping(uint256 => PetBonk) petBonk;
    mapping(uint256 => mapping(bytes32 => bool)) petUsedCommit;
}

library LibBonkStorage {
    bytes32 internal constant DIAMOND_BONK_STORAGE_POSITION =
        keccak256("diamond.bonk.storage");

    function bonkStorage() internal pure returns (BonkStorage storage ds) {
        bytes32 position = DIAMOND_BONK_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
}
