// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {Context, Ownable} from "./Ownable.sol";
import {MerkleProof} from "./MerkleProof.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Pausable} from "./Pausable.sol";

contract MerkleWhitelist is Ownable {
    bytes32 public merkleRoot;
    mapping(address => bool) internal whitelist;

    function registerMerkleRoot(bytes32 root) external onlyOwner {
        merkleRoot = root;
    }

    function isWhitelisted(
        address _who,
        bytes32[] memory proof
    ) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encode(_who));
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }

    modifier checkWhitelist(address _who, bytes32[] memory proof) {
        if (whitelist[_who]) {
            _;
            return;
        }

        require(isWhitelisted(_who, proof), "not in whitelist");
        whitelist[_who] = true;
        _;
    }
}

