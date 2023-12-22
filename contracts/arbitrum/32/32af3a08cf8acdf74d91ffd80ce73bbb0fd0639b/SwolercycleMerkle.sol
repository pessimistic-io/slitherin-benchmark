// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./Ownable.sol";
import "./MerkleProof.sol";
import "./Swolercycle.sol";

contract SwolercycleMerkle is Ownable {
    struct Claim {
        bool claimedAll;
        uint256 leftToClaim;
    }

    mapping(bytes32 => Claim) public claimed;

    bytes32 public merkleRoot;

    Swolercycle public swolercycle;

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

    function mintSwolercycle(bytes32[] memory proof, uint256 amount) public {
        bytes32 proofHash = keccak256(abi.encodePacked(proof));

        require(
            !claimed[proofHash].claimedAll,
            "SwolercycleMerkle: already claimed"
        );

        if (claimed[proofHash].leftToClaim == 0) {
            claimed[proofHash].leftToClaim = amount;
        }

        uint256 _leftToClaim = claimed[proofHash].leftToClaim;
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));

        require(
            MerkleProof.verify(proof, merkleRoot, leaf),
            "SwolercycleMerkle: proof invalid"
        );

        uint256 batchSize = _leftToClaim > 20 ? 20 : _leftToClaim;

        claimed[proofHash].leftToClaim -= batchSize;

        if (claimed[proofHash].leftToClaim == 0) {
            claimed[proofHash].claimedAll = true;
        }

        for (uint256 i = 0; i < batchSize; i++) {
            swolercycle.mint(msg.sender);
        }
    }

    function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setSwolercycle(address _swolercycle) external onlyOwner {
        swolercycle = Swolercycle(_swolercycle);
    }
}

