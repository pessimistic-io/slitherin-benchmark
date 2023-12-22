// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./Ownable.sol";
import "./MerkleProof.sol";
import "./SmolBrainsPets.sol";

contract MerkleAirdropBrains is Ownable {
    struct Claim {
        bool claimedAll;
        uint256 leftToClaim;
    }

    mapping(bytes32 => Claim) public claimed;

    bytes32 public merkleRoot;

    SmolBrainsPets public smolBrainsPets;

    function leftToClaim(bytes32[] memory proof, uint256 amount)
        public
        view
        returns (uint256)
    {
        bytes32 proofHash = keccak256(abi.encodePacked(proof));

        if (claimed[proofHash].claimedAll) return 0;

        if (claimed[proofHash].leftToClaim == 0) {
            return amount;
        } else {
            return claimed[proofHash].leftToClaim;
        }
    }

    function mintSmolPet(bytes32[] memory proof, uint256 amount) public {
        bytes32 proofHash = keccak256(abi.encodePacked(proof));

        require(
            !claimed[proofHash].claimedAll,
            "MerkleAirdropBrains: already claimed"
        );

        if (claimed[proofHash].leftToClaim == 0) {
            claimed[proofHash].leftToClaim = amount;
        }

        uint256 _leftToClaim = claimed[proofHash].leftToClaim;
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));

        require(
            MerkleProof.verify(proof, merkleRoot, leaf),
            "MerkleAirdropBrains: proof invalid"
        );

        uint256 batchSize = _leftToClaim > 20 ? 20 : _leftToClaim;

        for (uint256 i = 0; i < batchSize; i++) {
            smolBrainsPets.mint(msg.sender);
        }

        claimed[proofHash].leftToClaim -= batchSize;

        if (claimed[proofHash].leftToClaim == 0) {
            claimed[proofHash].claimedAll = true;
        }
    }

    function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setSmolBrainsPets(address _smolBrainsPets) external onlyOwner {
        smolBrainsPets = SmolBrainsPets(_smolBrainsPets);
    }
}

