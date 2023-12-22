// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import { Ownable } from "./Ownable.sol";
import { Token18, Token18Lib, UFixed18 } from "./Token18.sol";
import { MerkleProof } from "./MerkleProof.sol";
import { ISeasonalMerkleClaim } from "./ISeasonalMerkleClaim.sol";

contract SeasonalMerkleClaim is ISeasonalMerkleClaim, Ownable {
    /// @notice Token being distributed in merkle drops
    Token18 public immutable token;

    /// @notice Mapping of merkle roots added by the owner
    mapping(bytes32 => bool) public merkleRoots;

    /// @notice Mapping of addresses who have claimed tokens
    mapping(address => mapping(bytes32 => bool)) public claimed;

    constructor(Token18 token_) {
        __Ownable__initialize();
        token = token_;
    }

    /// @notice Used to claim tokens for multiple seasons
    /// @param amounts of each leaf to claim
    /// @param roots of each merkle season to claim
    /// @param proofs of each merkle season to claim
    function claim(
        UFixed18[] calldata amounts,
        bytes32[] calldata roots,
        bytes32[][] calldata proofs
    ) external returns (UFixed18 claimedAmount) {
        for (uint256 i = 0; i < roots.length; i++)
            claimedAmount = claimedAmount.add(_claim(amounts[i], roots[i], proofs[i]));

        token.push(msg.sender, claimedAmount);
    }

    /// @notice Internal claim logic for a single
    /// @param amount to claim
    /// @param root of merkle tree to claim
    /// @param proof of merkle tree to claim
    function _claim(
        UFixed18 amount,
        bytes32 root,
        bytes32[] calldata proof
    ) private returns (UFixed18 claimedAmount) {
        if (!merkleRoots[root]) revert InvalidRoot(root);
        if (claimed[msg.sender][root]) revert AlreadyClaimed();

        /// @dev The current OpenZeppelin standard is to hash the leaf data twice
        /// https://github.com/OpenZeppelin/merkle-tree#leaf-hash
        if (!MerkleProof.verifyCalldata(
            proof,
            root,
            keccak256(bytes.concat(keccak256(abi.encode(msg.sender, amount))))
        )) revert InvalidClaim(msg.sender, root);

        claimed[msg.sender][root] = true;
        claimedAmount = amount;

        emit Claimed(msg.sender, root, amount);
    }

    /// @notice Owner function to add a merkle tree root
    /// @param root to whitelist
    function addRoot(bytes32 root) external onlyOwner {
        emit RootAdded(root);
        merkleRoots[root] = true;
    }

    /// @notice Owner function to remove a merkle tree root
    /// @param root to invalidate
    function removeRoot(bytes32 root) external onlyOwner {
        emit RootRemoved(root);
        merkleRoots[root] = false;
    }

    /// @notice Owner function to remove drop tokens sitting in contract
    /// @param amount to push to owner
    function withdrawToken(UFixed18 amount) external onlyOwner {
        token.push(msg.sender, amount);
    }
}

