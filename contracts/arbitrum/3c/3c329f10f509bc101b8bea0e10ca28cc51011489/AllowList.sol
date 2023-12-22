// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {Ownable} from "./Ownable.sol";
import {MerkleProof} from "./MerkleProof.sol";

contract AllowList is Ownable {
    bytes32 public merkleRoot;
    mapping(bytes32 => bool) public merkleRootUsed;
    mapping(address => bool) public isUserMinted;

    constructor(bytes32 _merkleRoot) {
        merkleRoot = _merkleRoot;
    }

    function setMerkleRoot(bytes32 newMerkleRoot) external onlyOwner {
        require(!merkleRootUsed[newMerkleRoot], "AllowList: Merkle root already used");
        merkleRoot = newMerkleRoot;
    }

    function isInAllowList(
        address user,
        bytes32[] calldata merkleProof
    ) public view returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(user));
        bool allowed = MerkleProof.verify(
            merkleProof,
            merkleRoot,
            node
        );

        if (allowed && !isUserMinted[user]) {
            return true;
        }
        return false;
    }
}
