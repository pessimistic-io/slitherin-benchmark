// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IEnumerableEscrow.sol";

/// @title A place to hide your stolen NFTs and earn some CounterfeitMoney
interface IStakingHideout is IEnumerableEscrow {
	/// @notice Emitted when a reward was payed to a staker
	/// @param user The staker
	/// @param reward The reward amount
	event RewardPaid(address indexed user, uint256 reward);

	/// @notice Emitted when a staker stakes an ERC721 token
	/// @param user The staker
	/// @param tokenId The token deposited
	event Stashed(address indexed user, uint256 indexed tokenId);

	/// @notice Emitted when a staker unstakes an ERC721 token
	/// @param user The staker
	/// @param tokenId The token deposited
	event Unstashed(address indexed user, uint256 indexed tokenId);

	/// @notice Deposits an approved stolen NFT into the contract if the hideout still has enough space
	/// @dev Emits a {Stashed} Event and updates token rewards
	/// @param tokenId The message senders approved token that should be staked
	function stash(uint256 tokenId) external;

	/// @notice Deposits a stolen NFT into the contract in a single call by providing a valid EIP-2612 Permit
	/// @dev Same as {xref-IStakingHideout-stash-uint256-}[`stash`], with additional signature parameters which
	/// allow the approval and transfer the StolenNFT in a single Transaction using EIP-2612 Permits
	/// Emits a {Stashed} Event and updates token rewards
	/// @param tokenId The message senders token that should be staked
	/// @param deadline timestamp until when the given signature will be valid
	/// @param v The parity of the y co-ordinate of r of the signature
	/// @param r The x co-ordinate of the r value of the signature
	/// @param s The x co-ordinate of the s value of the signature
	function stashWithPermit(
		uint256 tokenId,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external;

	/// @notice Transfers the staked stolen NFT back to the staker
	/// @dev Emits a {Unstashed} Event and updates token rewards
	/// @param tokenId The message senders approved token that should be staked
	function unstash(uint256 tokenId) external;

	/// @notice Get the staker of a staked StolenNFT
	/// @param tokenId The tokenId of the StolenNFT that was staked
	/// @return The address of the staker
	function getStaker(uint256 tokenId) external view returns (address);

	/// @notice Transfers the collected staking rewards to the message sender
	function getReward() external;

	/// @notice Returns the rewards payed per token
	/// @return amount of reward per token
	function rewardPerToken() external view returns (uint256);

	/// @notice Returns the rewards earned for a given account
	/// @return The amount of rewards earned by an user
	function earned(address account) external view returns (uint256);
}

