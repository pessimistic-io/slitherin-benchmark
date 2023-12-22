// SPDX-License-Identifier: MIT
pragma solidity 0.8;

library MerkleVerifier {
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf, uint256 index) internal pure returns (bool) {
        bytes32 node = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (index % 2 == 0) {
                node = keccak256(abi.encodePacked(node, proofElement));
            } else {
                node = keccak256(abi.encodePacked(proofElement, node));
            }

            index = index / 2;
        }

        return node == root;
    }
}

