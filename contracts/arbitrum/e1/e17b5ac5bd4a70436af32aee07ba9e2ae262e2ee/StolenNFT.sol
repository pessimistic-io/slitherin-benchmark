// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC721Enumerable.sol";
import "./ERC721Permit.sol";
import "./IStolenNFT.sol";
import "./ICriminalRecords.sol";

error AlreadyStolen(uint256 tokenId);
error CallerNotTheLaw();
error CriminalRecordsOffline();
error CrossChainUriMissing();
error ErrorSendingTips();
error InvalidChainId();
error InvalidRoyalty();
error NothingLeftToSteal();
error NoTips();
error ReceiverIsRetired();
error SenderIsRetired();
error StealingFromZeroAddress();
error StealingStolenNft();
error ThiefIsRetired();
error UnsupportedToken();
error YouAreRetired();
error YouAreWanted();

/// @title Steal somebody's NFTs (with their permission of course)
/// @dev ERC721 Token supporting EIP-2612 signatures for token approvals
contract StolenNFT is IStolenNFT, Ownable, ERC721Permit, ERC721Enumerable {
	/// Contract used to track the thief's action
	ICriminalRecords public criminalRecords;
	/// Maximum supply of stolen NFTs
	uint256 public maximumSupply;
	/// Used for unique stolen token ids
	uint256 private _tokenCounter;
	/// Mapping from the original address & token id hash to a StolenNFT token id
	mapping(bytes32 => uint256) private _stolenNfts;
	/// Mapping from a StolenNFT token id to a struct containing the original address & token id
	mapping(uint256 => NftData) private _stolenNftsById;
	/// Optional mapping of StolenNFTs token ids to tokenURIs
	mapping(uint256 => string) private _tokenURIs;
	/// Mapping of thief's to whether they are retired to disable interaction / transfer with StolenNFTs
	mapping(address => bool) private _retiredThief;

	constructor(address _owner) Ownable(_owner) ERC721Permit("StolenNFT", "SNFT") {
		maximumSupply = type(uint256).max;
	}

	receive() external payable {}

	/// @inheritdoc IStolenNFT
	function steal(
		uint64 originalChainId,
		address originalAddress,
		uint256 originalId,
		address mintFrom,
		uint32 royaltyFee,
		string memory uri
	) external payable override returns (uint256) {
		if (retired(msg.sender)) revert YouAreRetired();
		if (totalSupply() >= maximumSupply) revert NothingLeftToSteal();
		if (originalAddress == address(0)) revert StealingFromZeroAddress();
		if (originalAddress == address(this)) revert StealingStolenNft();
		if (originalChainId == 0 || originalChainId > type(uint64).max / 2 - 36)
			revert InvalidChainId();
		if ((royaltyFee > 0 && originalChainId != block.chainid) || royaltyFee > 10000)
			revert InvalidRoyalty();

		bytes32 nftHash = keccak256(abi.encodePacked(originalAddress, originalId));
		if (_stolenNfts[nftHash] != 0) revert AlreadyStolen(_stolenNfts[nftHash]);

		uint256 stolenId = ++_tokenCounter;

		// Set the tokenUri if given
		if (bytes(uri).length > 0) {
			_tokenURIs[stolenId] = uri;
		} else if (originalChainId != block.chainid) {
			revert CrossChainUriMissing();
		}

		// Store the bi-directional mapping between original contract and token id
		_stolenNfts[nftHash] = stolenId;
		_stolenNftsById[stolenId] = NftData(
			royaltyFee,
			originalChainId,
			originalAddress,
			originalId
		);

		emit Stolen(msg.sender, originalChainId, originalAddress, originalId, stolenId);

		// Skip sleep minting if callers address is given
		if (mintFrom == msg.sender) mintFrom = address(0);

		// Same as mint + additional Transfer event
		_sleepMint(mintFrom, msg.sender, stolenId);

		address originalOwner;
		if (originalChainId == block.chainid) {
			// Fetch the original owner if on same chain
			originalOwner = originalOwnerOf(originalAddress, originalId);

			// Check if fetching the original tokenURI is supported if no URI is given
			if (bytes(uri).length == 0) {
				uri = originalTokenURI(originalAddress, originalId);
				if (bytes(uri).length == 0) {
					revert UnsupportedToken();
				}
			}
		}

		// Track the wanted level if a thief who is not the owner steals it
		if (address(criminalRecords) != address(0) && msg.sender != originalOwner) {
			criminalRecords.crimeWitnessed(msg.sender);
		}

		return stolenId;
	}

	/// @inheritdoc IStolenNFT
	function swatted(uint256 stolenId) external override {
		if (msg.sender != address(criminalRecords)) revert CallerNotTheLaw();
		if (retired(ERC721.ownerOf(stolenId))) revert ThiefIsRetired();
		_burn(stolenId);
	}

	/// @inheritdoc IStolenNFT
	function surrender(uint256 stolenId) external override onlyHolder(stolenId) {
		_burn(stolenId);

		if (address(criminalRecords) != address(0)) {
			criminalRecords.surrender(msg.sender);
		}
	}

	/// @notice Allows holder of the StolenNFT to overwrite the linked / stored tokenURI
	/// @param stolenId The token ID of the StolenNFT
	/// @param uri The new tokenURI that should be returned when tokenURI() is called or
	/// no uri if the nft originates from the same chain and the originals tokenURI should be linked
	function setTokenURI(uint256 stolenId, string memory uri) external onlyHolder(stolenId) {
		if (bytes(uri).length > 0) {
			_tokenURIs[stolenId] = uri;
			return;
		}

		NftData storage data = _stolenNftsById[stolenId];
		if (data.chainId == block.chainid) {
			// Only allow linking if the original token returns an uri
			uri = originalTokenURI(data.contractAddress, data.tokenId);
			if (bytes(uri).length == 0) {
				revert UnsupportedToken();
			}
			delete _tokenURIs[stolenId];
		} else {
			revert CrossChainUriMissing();
		}
	}

	/// @notice While thief's are retired stealing / sending is not possible
	/// This protects them from NFTs being sent to their address, increasing their wanted level
	/// @param isRetired Whether msg.sender is retiring or becoming a thief again
	function retire(bool isRetired) external {
		if (address(criminalRecords) == address(0)) revert CriminalRecordsOffline();
		if (criminalRecords.getWanted(msg.sender) > 0) revert YouAreWanted();

		_retiredThief[msg.sender] = isRetired;
	}

	/// @notice Sets the maximum amount of StolenNFTs that can be minted / stolen
	/// @dev Can only be set by the contract owner, emits a SupplyChange event
	/// @param _maximumSupply The new maximum supply
	function setMaximumSupply(uint256 _maximumSupply) external onlyOwner {
		maximumSupply = _maximumSupply;
		emit SupplyChange(_maximumSupply);
	}

	/// @notice Sets the criminal records contract that should be used to track thefts
	/// @dev Can only be set by the contract owner
	/// @param recordsAddress The address of the contract
	function setCriminalRecords(address recordsAddress) external onlyOwner {
		criminalRecords = ICriminalRecords(recordsAddress);
		emit CriminalRecordsChange(recordsAddress);
	}

	/// @notice Sends all collected tips to a specified address
	/// @dev Can only be executed by the contract owner
	/// @param recipient Payable address that should receive all tips
	function emptyTipJar(address payable recipient) external onlyOwner {
		if (recipient == address(0)) revert TransferToZeroAddress();
		uint256 amount = address(this).balance;
		if (amount == 0) revert NoTips();
		(bool success, ) = recipient.call{value: amount}("");
		if (!success) revert ErrorSendingTips();
	}

	/// @inheritdoc IStolenNFT
	function getStolen(address originalAddress, uint256 originalId)
		external
		view
		override
		returns (uint256)
	{
		return _stolenNfts[keccak256(abi.encodePacked(originalAddress, originalId))];
	}

	/// @inheritdoc IStolenNFT
	function getOriginal(uint256 stolenId)
		external
		view
		override
		returns (
			uint64,
			address,
			uint256
		)
	{
		return (
			_stolenNftsById[stolenId].chainId,
			_stolenNftsById[stolenId].contractAddress,
			_stolenNftsById[stolenId].tokenId
		);
	}

	/// @inheritdoc IERC721Metadata
	function tokenURI(uint256 tokenId)
		public
		view
		override(IERC721Metadata, ERC721)
		returns (string memory)
	{
		if (!_exists(tokenId)) revert QueryForNonExistentToken(tokenId);

		if (bytes(_tokenURIs[tokenId]).length > 0) {
			return _tokenURIs[tokenId];
		}

		return
			originalTokenURI(
				_stolenNftsById[tokenId].contractAddress,
				_stolenNftsById[tokenId].tokenId
			);
	}

	/// @notice Returns the original tokenURI of an IERC721Metadata token
	/// @dev External call that can be influenced by caller, handle with care
	/// @param contractAddress The contract address of the NFT
	/// @param tokenId The token id of the NFT
	/// @return If the contract is a valid IERC721Metadata token the tokenURI will be returned,
	/// an empty string otherwise
	function originalTokenURI(address contractAddress, uint256 tokenId)
		public
		view
		returns (string memory)
	{
		if (contractAddress.code.length > 0) {
			try IERC721Metadata(contractAddress).tokenURI(tokenId) returns (
				string memory fetchedURI
			) {
				return fetchedURI;
			} catch {}
		}

		return "";
	}

	/// @notice Returns the original owner of an IERC721 token if the owner is not a contract
	/// @dev External call that can be influenced by caller, handle with care
	/// @param contractAddress The contract address of the NFT
	/// @param tokenId The token id of the NFT
	/// @return If the contract is a valid IERC721 token that exists the address will be returned
	/// if its not an contract address, zero-address otherwise
	function originalOwnerOf(address contractAddress, uint256 tokenId)
		public
		view
		returns (address)
	{
		if (contractAddress.code.length > 0) {
			try IERC721(contractAddress).ownerOf(tokenId) returns (address _holder) {
				if (_holder.code.length == 0) {
					return _holder;
				}
			} catch {}
		}

		return address(0);
	}

	/// @notice Returns whether a thief is retired
	/// @param thief The thief who should be checked out
	/// @return True if criminal records are online and the thief is retired, false otherwise
	function retired(address thief) public view returns (bool) {
		return address(criminalRecords) != address(0) && _retiredThief[thief];
	}

	/// @inheritdoc IERC2981
	function royaltyInfo(uint256 tokenId, uint256 salePrice)
		public
		view
		virtual
		override
		returns (address, uint256)
	{
		address holder;
		uint256 royaltyValue;
		NftData storage data = _stolenNftsById[tokenId];

		if (data.tokenRoyalty > 0 && data.tokenRoyalty <= 10000) {
			// Only non holders that are not contracts will be compensated
			holder = originalOwnerOf(data.contractAddress, data.tokenId);

			if (holder != address(0)) {
				royaltyValue = (salePrice * data.tokenRoyalty) / 10000;
			}
		}

		return (holder, royaltyValue);
	}

	/// @inheritdoc IERC165
	function supportsInterface(bytes4 interfaceId)
		public
		view
		virtual
		override(IERC165, ERC721, ERC721Enumerable)
		returns (bool)
	{
		return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
	}

	/// @inheritdoc ERC721
	function _burn(uint256 tokenId) internal override(ERC721) {
		NftData storage data = _stolenNftsById[tokenId];

		emit Seized(
			ERC721.ownerOf(tokenId),
			data.chainId,
			data.contractAddress,
			data.tokenId,
			tokenId
		);

		delete _stolenNfts[keccak256(abi.encodePacked(data.contractAddress, data.tokenId))];
		delete _stolenNftsById[tokenId];

		if (bytes(_tokenURIs[tokenId]).length > 0) {
			delete _tokenURIs[tokenId];
		}

		super._burn(tokenId);
	}

	/// @inheritdoc ERC721
	function _beforeTokenTransfer(
		address from,
		address to,
		uint256 tokenId
	) internal virtual override(ERC721, ERC721Enumerable) {
		super._beforeTokenTransfer(from, to, tokenId);
	}

	/// @inheritdoc ERC721
	function _afterTokenTransfer(
		address from,
		address to,
		uint256 tokenId
	) internal virtual override(ERC721) {
		super._afterTokenTransfer(from, to, tokenId);

		// Prohibit retired thief's from transferring
		// Track the exchange except if the original holder is transferring it
		if (address(criminalRecords) != address(0) && from != address(0)) {
			if (_retiredThief[from]) revert SenderIsRetired();
			if (_retiredThief[to]) revert ReceiverIsRetired();

			criminalRecords.exchangeWitnessed(from, to);
		}
	}

	/// @dev Modifier that verifies that msg.sender is the owner of the StolenNFT
	/// @param stolenId The token id of the StolenNFT
	modifier onlyHolder(uint256 stolenId) {
		address holder = ERC721.ownerOf(stolenId);
		if (msg.sender != holder) revert NotTheTokenOwner();
		if (retired(msg.sender)) revert YouAreRetired();
		_;
	}

	/// @notice Emitted when the maximum supply of StolenNFTs changes
	/// @param newSupply the new maximum supply
	event SupplyChange(uint256 newSupply);

	/// @notice Emitted when the criminalRecords get set or unset
	/// @param recordsAddress The new address of the CriminalRecords or zero address if disabled
	event CriminalRecordsChange(address recordsAddress);
}

