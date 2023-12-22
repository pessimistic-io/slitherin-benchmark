// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IEnumerableEscrow.sol";

/// @title A place where bad people do bad deals
interface IBlackMarket is IEnumerableEscrow {
	/// @notice Emitted when a user lists a StolenNFT
	/// @param seller The user who lists the StolenNFT
	/// @param tokenId The token ID of the listed StolenNFT
	/// @param price The listing price
	event Listed(address indexed seller, uint256 indexed tokenId, uint256 price);

	/// @notice Emitted when a user canceled a listed StolenNFT
	/// @param seller The user who listed the StolenNFT / canceled the listing
	/// @param tokenId The token ID of the listed StolenNFT
	/// @param price The original listing price
	event Canceled(address indexed seller, uint256 indexed tokenId, uint256 price);

	/// @notice Emitted when the market closes or opens
	/// @param state Whether the market closed or opened
	event MarketClosed(bool state);

	/// @notice Emitted when a user sells a StolenNFT
	/// @param buyer The user who buys the StolenNFT
	/// @param seller The user who sold the StolenNFT
	/// @param tokenId The token ID of the sold StolenNFT
	/// @param price The paid price
	event Sold(
		address indexed buyer,
		address indexed seller,
		uint256 indexed tokenId,
		uint256 price
	);

	/// @notice Struct to stores a listings seller and price
	struct Listing {
		address seller;
		uint256 price;
	}

	/// @notice Buy a listed StolenNFT on the market
	/// @dev Emits a {Sold} Event
	/// @param tokenId The token id of the StolenNFT to buy
	function buy(uint256 tokenId) external;

	/// @notice Buy a listed NFT on the market by providing a valid EIP-2612 Permit for the Money transaction
	/// @dev Same as {xref-IBlackMarket-buy-uint256-}[`buy`], with additional signature parameters which
	/// allow the approval and transfer of CounterfeitMoney in a single Transaction using EIP-2612 Permits
	/// Emits a {Sold} Event
	/// @param tokenId The token id of the StolenNFT to buy
	/// @param deadline timestamp until when the given signature will be valid
	/// @param v The parity of the y co-ordinate of r of the signature
	/// @param r The x co-ordinate of the r value of the signature
	/// @param s The x co-ordinate of the s value of the signature
	function buyWithPermit(
		uint256 tokenId,
		uint256 price,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external;

	/// @notice List a StolenNFT on the market
	/// @dev Emits a {Listed} Event
	/// @param tokenId The token id of the StolenNFT to list
	/// @param price The price the StolenNFT should be listed for
	function listNft(uint256 tokenId, uint256 price) external;

	/// @notice List a StolenNFT on the market by providing a valid EIP-2612 Permit for the token transaction
	/// @dev Same as {xref-IBlackMarket-listNft-uint256-uint256-}[`listNft`], with additional signature parameters which
	/// allow the approval and transfer of CounterfeitMoney in a single Transaction using EIP-2612 Permits
	/// Emits a {Listed} Event
	/// @param tokenId The token id of the StolenNFT to list
	/// @param price The price the StolenNFT should be listed for
	/// @param deadline timestamp until when the given signature will be valid
	/// @param v The parity of the y co-ordinate of r of the signature
	/// @param r The x co-ordinate of the r value of the signature
	/// @param s The x co-ordinate of the s value of the signature
	function listNftWithPermit(
		uint256 tokenId,
		uint256 price,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external;

	/// @notice Update an existing listing on the market
	/// @dev Emits a {Listed} Event
	/// @param tokenId The token id of the StolenNFT that is already listed
	/// @param newPrice The new price the StolenNFT
	function updateListing(uint256 tokenId, uint256 newPrice) external;

	/// @notice Cancel an existing listing on the market
	/// @dev Emits a {Canceled} Event
	/// @param tokenId The token id of the listed StolenNFT that should be canceled
	function cancelListing(uint256 tokenId) external;

	/// @notice Allows the market to be closed, disabling listing and buying
	/// @param _marketClosed Whether the market should be closed or opened
	function closeMarket(bool _marketClosed) external;

	/// @notice Get an existing listing on the market by its tokenId
	/// @param tokenId The token id of the listed StolenNFT that should be retrieved
	function getListing(uint256 tokenId) external view returns (Listing memory);
}

