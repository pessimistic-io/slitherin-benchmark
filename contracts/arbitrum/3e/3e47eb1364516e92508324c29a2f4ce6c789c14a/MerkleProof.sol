pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "./Ownable.sol";

// Sourced from https://github.com/miguelmota/merkletreejs-solidity!
contract MerkleProof is Ownable {

  bytes32 root;

  function setRoot(bytes32 _root) external onlyOwner {
    root = _root;
  }

  function verify(bytes32 leaf, bytes32[] memory proof) external view returns (bool) {
    bytes32 computedHash = leaf;

    for (uint256 i = 0; i < proof.length; i++) {
      bytes32 proofElement = proof[i];

      if (computedHash <= proofElement) {
        // Hash(current computed hash + current element of the proof)
        computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
      } else {
        // Hash(current element of the proof + current computed hash)
        computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
      }
    }

    // Check if the computed hash (root) is equal to the provided root
    return computedHash == root;
  }
}
