// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./EnumerableEscrow.sol";
import "./ICounterfeitMoney.sol";
import "./IStolenNFT.sol";
import "./IBlackMarket.sol";

error MarketIsClosed();
error NotTheSeller();
error NotTheTokenOwner();
error TokenNotListed();
error TransactionFailed();

/// @title A place where bad people do bad deals
contract BlackMarket is IBlackMarket, EnumerableEscrow, Ownable {
	/// ERC20 Token used to pay for a listing
	ICounterfeitMoney public money;
	/// ERC721 Token that is listed for sale
	IStolenNFT public stolenNFT;
	/// Whether listing / buying is possible
	bool public marketClosed;

	/// Mappings between listed tokenIds and listings seller and price
	mapping(uint256 => Listing) private listings;

	constructor(
		address _owner,
		address _stolenNFT,
		address _money
	) Ownable(_owner) {
		stolenNFT = IStolenNFT(_stolenNFT);
		money = ICounterfeitMoney(_money);
	}

	/// @inheritdoc IBlackMarket
	function buyWithPermit(
		uint256 tokenId,
		uint256 price,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external override {
		money.permit(msg.sender, address(this), price, deadline, v, r, s);
		buy(tokenId);
	}

	/// @inheritdoc IBlackMarket
	function listNftWithPermit(
		uint256 tokenId,
		uint256 price,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external override {
		stolenNFT.permit(msg.sender, address(this), tokenId, deadline, v, r, s);
		listNft(tokenId, price);
	}

	/// @inheritdoc IBlackMarket
	function updateListing(uint256 tokenId, uint256 newPrice) external override {
		Listing storage listing = listings[tokenId];
		if (msg.sender != listing.seller) revert NotTheSeller();

		listing.price = newPrice;

		emit Listed(msg.sender, tokenId, newPrice);
	}

	/// @inheritdoc IBlackMarket
	function cancelListing(uint256 tokenId) external override {
		Listing memory listing = listings[tokenId];
		if (msg.sender != listing.seller && msg.sender != Ownable.owner()) revert NotTheSeller();

		_unlist(listing.seller, tokenId);
		emit Canceled(listing.seller, tokenId, listing.price);

		stolenNFT.transferFrom(address(this), listing.seller, tokenId);
	}

	/// @inheritdoc IBlackMarket
	function closeMarket(bool _marketClosed) external override onlyOwner {
		marketClosed = _marketClosed;
		emit MarketClosed(_marketClosed);
	}

	/// @inheritdoc IBlackMarket
	function getListing(uint256 tokenId) external view override returns (Listing memory) {
		if (listings[tokenId].seller == address(0)) revert TokenNotListed();
		return listings[tokenId];
	}

	/// @inheritdoc IBlackMarket
	function listNft(uint256 tokenId, uint256 price) public override {
		if (stolenNFT.ownerOf(tokenId) != msg.sender) revert NotTheTokenOwner();
		if (marketClosed) revert MarketIsClosed();

		_list(msg.sender, tokenId, price);
		emit Listed(msg.sender, tokenId, price);

		stolenNFT.transferFrom(msg.sender, address(this), tokenId);
	}

	/// @inheritdoc IBlackMarket
	function buy(uint256 tokenId) public override {
		Listing memory listing = listings[tokenId];
		if (listing.seller == address(0)) revert TokenNotListed();
		if (marketClosed) revert MarketIsClosed();

		_unlist(listing.seller, tokenId);
		emit Sold(msg.sender, listing.seller, tokenId, listing.price);

		(address royaltyReceiver, uint256 royaltyShare) = stolenNFT.royaltyInfo(
			tokenId,
			listing.price
		);

		if (royaltyShare > 0) {
			bool sentRoyalty = money.transferFrom(msg.sender, royaltyReceiver, royaltyShare);
			if (!sentRoyalty) revert TransactionFailed();
		}

		bool sent = money.transferFrom(msg.sender, listing.seller, listing.price - royaltyShare);
		if (!sent) revert TransactionFailed();

		stolenNFT.transferFrom(address(this), msg.sender, tokenId);
	}

	/// @dev Adds the listed NFT to the listings and enumerations mapping
	/// @param seller The listings seller
	/// @param tokenId The listed token
	/// @param price The listings price
	function _list(
		address seller,
		uint256 tokenId,
		uint256 price
	) internal {
		listings[tokenId] = Listing(seller, price);
		EnumerableEscrow._addTokenToEnumeration(seller, tokenId);
	}

	/// @dev Removes the listed NFT to the listings and enumerations mapping
	/// @param seller The listings seller
	/// @param tokenId The listed token
	function _unlist(address seller, uint256 tokenId) internal {
		delete listings[tokenId];
		EnumerableEscrow._removeTokenFromEnumeration(seller, tokenId);
	}
}

