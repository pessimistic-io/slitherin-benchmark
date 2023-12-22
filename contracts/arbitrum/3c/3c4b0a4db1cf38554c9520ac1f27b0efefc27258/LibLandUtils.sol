// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

// Library imports
import { MerkleProof } from "./MerkleProof.sol";

// Storage imports
import { LibStorage, WastelandStorage } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";
import { ERC721BaseStorage } from "./ERC721BaseStorage.sol";

library LibLandUtils {
    using ERC721BaseStorage for ERC721BaseStorage.Layout;

    function ws() internal pure returns (WastelandStorage storage) {
        return LibStorage.wastelandStorage();
    }

    function verifyProof(
        uint256 index,
        address account,
        uint256[] memory tokens,
        bytes32[] memory merkleProof
    ) internal view {
        if (ws().wastelandsWhitelistMinted[account]) revert Errors.WastelandsAlreadyMinted();
        if (!_verifyMerkleProof(_leaf(index, account, tokens), merkleProof)) revert Errors.InvalidSignature();
    }

    function _leaf(uint256 index, address account, uint256[] memory tokens) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(index, account, tokens));
    }

    function _verifyMerkleProof(bytes32 leaf, bytes32[] memory proof) internal view returns (bool) {
        return MerkleProof.verify(proof, ws().mintMerkleRoot, leaf);
    }
}

