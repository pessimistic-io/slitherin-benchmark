// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";

/**
 * Contract which implements a merkle tree containing addresses
 * Addresses included in this list are eligible to claim xToken L2 NFTs
 */
contract MerkleTree is Ownable {
    bytes32 root; // merkle tree root

    constructor(bytes32 _root) {
        root = _root;
    }

    // Change root to update whitelist
    function updateRoot(bytes32 newRoot) external onlyOwner {
        root = newRoot;
    }

    // Verify address is in merkle tree
    // Requires sending merkle proof to the function
    function verify(address recipient, bytes32[] memory merkleProof)
        external
        view
    {
        // Compute the merkle leaf from recipient
        bytes32 leaf = keccak256(abi.encodePacked(recipient));
        // verify the proof is valid
        require(
            MerkleProof.verify(merkleProof, root, leaf),
            "Proof is not valid"
        );
    }
}

