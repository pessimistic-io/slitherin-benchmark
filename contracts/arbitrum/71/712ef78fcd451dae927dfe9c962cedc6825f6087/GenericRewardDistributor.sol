// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { MerkleProof } from "./MerkleProof.sol";
import { IGenericRewardDistributor } from "./IGenericRewardDistributor.sol";
import { SafeERC20, IERC20 } from "./SafeERC20.sol";
import { OwnableWithTransfer } from "./OwnableWithTransfer.sol";

// import "hardhat/console.sol";

/// @notice This contract distrubutes tokne rewards using a merkle tree
contract GenericRewardDistributor is OwnableWithTransfer, IGenericRewardDistributor {
	using SafeERC20 for IERC20;

	/// @dev Returns the token distributed by the contract
	IERC20 public immutable override token;

	/// @dev The current merkle root of total claimable balances
	bytes32 public override merkleRoot;

	/// @dev The mapping that stores amounts already claimed by users
	mapping(address => uint256) public claimed;

	/// @param token_ ERC20 token to distribute
	/// @param merkleRoot_ The merkle root of the total claimable balances
	constructor(address token_, bytes32 merkleRoot_) OwnableWithTransfer(msg.sender) {
		token = IERC20(token_);
		merkleRoot = merkleRoot_;
	}

	/// @notice Updates the merkle root - this can be used to increment total reward amounts
	/// @param newRoot The new merkle root
	function updateMerkleRoot(bytes32 newRoot) external onlyOwner {
		bytes32 oldRoot = merkleRoot;
		merkleRoot = newRoot;
		emit RootUpdated(oldRoot, newRoot);
	}

	/// @notice Claims the given amount of the token for the account. Reverts if the inputs are not a leaf in the tree
	/// @param account The account to claim for
	/// @param totalAmount The total amount of token to claim
	/// @param merkleProof The merkle proof of the claim
	function claim(
		address account,
		uint256 totalAmount,
		bytes32[] calldata merkleProof
	) public override {
		require(merkleRoot != bytes32(0), "MerkleDistributor: No merkle root set");
		require(claimed[account] < totalAmount, "MerkleDistributor: Nothing to claim");

		bytes32 node = keccak256(bytes.concat(keccak256(abi.encode(account, totalAmount))));

		require(
			MerkleProof.verify(merkleProof, merkleRoot, node),
			"MerkleDistributor: Invalid proof."
		);

		uint256 claimedAmount = totalAmount - claimed[account];
		claimed[account] += claimedAmount;

		IERC20(token).safeTransfer(account, claimedAmount);
		emit Claimed(account, claimedAmount, false);
	}
}

