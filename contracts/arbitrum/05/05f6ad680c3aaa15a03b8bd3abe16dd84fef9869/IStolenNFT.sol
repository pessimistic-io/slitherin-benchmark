// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC721Enumerable.sol";
import "./IERC721Metadata.sol";
import "./IERC721.sol";
import "./IERC2981.sol";
import "./IERC721Permit.sol";

/// @title Steal somebody's NFTs (with their permission of course)
/// @dev ERC721 Token supporting EIP-2612 signatures for token approvals
interface IStolenNFT is IERC2981, IERC721Metadata, IERC721Enumerable, IERC721Permit {
	/// @notice Emitted when a user steals / mints a NFT
	/// @param thief The user who stole a NFT
	/// @param originalChainId The chain the Nft was stolen from
	/// @param originalContract The original NFTs contract address
	/// @param originalId The original NFTs token ID
	/// @param stolenId The token ID of the minted StolenNFT
	event Stolen(
		address indexed thief,
		uint64 originalChainId,
		address indexed originalContract,
		uint256 indexed originalId,
		uint256 stolenId
	);

	/// @notice Emitted when a user was reported and gets his StolenNFT taken away / burned
	/// @param thief The user who returned the StolenNFT
	/// @param originalChainId The chain the Nft was stolen from
	/// @param originalContract The original NFTs contract address
	/// @param originalId The original NFTs token ID
	/// @param stolenId The token ID of the StolenNFT
	event Seized(
		address indexed thief,
		uint64 originalChainId,
		address originalContract,
		uint256 originalId,
		uint256 indexed stolenId
	);

	/// @notice Struct to store the contract and token ID of the NFT that was stolen
	struct NftData {
		uint32 tokenRoyalty;
		uint64 chainId;
		address contractAddress;
		uint256 tokenId;
	}

	/// @notice Steal / Mint an original NFT to create a StolenNFT
	/// @dev Emits a Stolen event
	/// @param originalChainId The chainId the NFT originates from, used to trace where the nft was stolen from
	/// @param originalAddress The original NFTs contract address
	/// @param originalId The original NFTs token ID
	/// @param mintFrom Optional address the StolenNFT will be minted and transferred from
	/// @param royaltyFee Optional royalty that should be payed to the original owner on secondary market sales
	/// @param uri Optional Metadata URI to overwrite / censor the original NFT
	function steal(
		uint64 originalChainId,
		address originalAddress,
		uint256 originalId,
		address mintFrom,
		uint32 royaltyFee,
		string memory uri
	) external payable returns (uint256);

	/// @notice Allows the StolenNFT to be taken away / burned by the authorities
	/// @dev Emits a Swatted event
	/// @param stolenId The token ID of the StolenNFT
	function swatted(uint256 stolenId) external;

	/// @notice Allows the holder to return / burn the StolenNFT
	/// @dev Emits a Swatted event
	/// @param stolenId The token ID of the StolenNFT
	function surrender(uint256 stolenId) external;

	/// @notice Returns the stolenID for a given original NFT address and tokenID if stolen
	/// @param originalAddress The contract address of the original NFT
	/// @param originalId The tokenID of the original NFT
	/// @return The stolenID
	function getStolen(address originalAddress, uint256 originalId)
		external
		view
		returns (uint256);

	/// @notice Returns the original NFT address and tokenID for a given stolenID if stolen
	/// @param stolenId The stolenID to lookup
	/// @return originalChainId The chain the NFT was stolen from
	/// @return originalAddress The contract address of the original NFT
	/// @return originalId The tokenID of the original NFT
	function getOriginal(uint256 stolenId)
		external
		view
		returns (
			uint64,
			address,
			uint256
		);
}

