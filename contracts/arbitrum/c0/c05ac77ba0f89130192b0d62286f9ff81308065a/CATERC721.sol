// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721.sol";
import "./IERC721Receiver.sol";
import "./ERC721Enumerable.sol";
import "./ERC721URIStorage.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./ERC721Burnable.sol";
import "./Counters.sol";
import "./Strings.sol";
import "./BytesLib.sol";
import "./WormholeStructs.sol";
import "./IWormhole.sol";
import "./IERC721Extended.sol";
import "./ICATERC721.sol";
import "./Structs.sol";
import "./Governance.sol";

contract CATERC721 is
Context,
ERC721,
IERC721Receiver,
ERC721Burnable,
ERC721URIStorage,
ERC721Enumerable,
CATERC721Governance,
CATERC721Events
{
	using Strings for uint256;
	
	constructor(string memory name, string memory symbol) ERC721(name, symbol) {
		setEvmChainId(block.chainid);
	}
	
	function initialize(
		uint16 chainId,
		address wormhole,
		uint8 finality,
		uint256 maxSupply,
		string memory base_uri
	) public onlyOwner {
		require(isInitialized() == false, "Already Initialized");
		setChainId(chainId);
		setWormhole(wormhole);
		setFinality(finality);
		setMaxSupply(maxSupply);
		setBaseUri(base_uri);
		setMintedSupply(0);
		setIsInitialized();
	}
	
	function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
		super._burn(tokenId);
	}
	
	function tokenURI(
		uint256 tokenId
	) public view override(ERC721, ERC721URIStorage) returns (string memory) {
		return super.tokenURI(tokenId);
	}
	
	function _baseURI() internal view virtual override returns (string memory) {
		return baseUri();
	}
	
	function supportsInterface(
		bytes4 interfaceId
	) public view override(ERC721, ERC721Enumerable) returns (bool) {
		return interfaceId == type(ICATERC721).interfaceId || super.supportsInterface(interfaceId);
	}
	
	function _beforeTokenTransfer(
		address from,
		address to,
		uint256 firstTokenId,
		uint256 batchSize
	) internal override(ERC721, ERC721Enumerable) {
		super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
	}
	
	function onERC721Received(
		address operator,
		address from,
		uint256 tokenId,
		bytes calldata data
	) public pure override returns (bytes4) {
		return this.onERC721Received.selector;
	}
	
	function bridgeOut(
		uint256 tokenId,
		uint16 _wormholeChainId,
		bytes32 recipient,
		uint32 nonce
	) external payable returns (uint64) {
		require(isInitialized() == true, "Not Initialized");
		require(evmChainId() == block.chainid, "unsupported fork");
		
		uint256 fee = wormhole().messageFee();
		require(msg.value >= fee, "Not enough fee provided to publish message");
		
		uint16 tokenChain = chainId();
		bytes32 tokenAddress = addressToBytes(address(this));
		string memory uriString = tokenURI(tokenId);
		
		CATERC721Structs.CrossChainPayload memory payload = CATERC721Structs.CrossChainPayload({
			tokenAddress: tokenAddress,
			tokenChain: tokenChain,
			tokenID: tokenId,
			uri: uriString,
			toAddress: recipient,
			toChain: _wormholeChainId
		});
		
		require(bytes(payload.uri).length <= 200, "tokenURI must not exceed 200 bytes");
		
		bytes memory encoded = encodeTransfer(payload);
		
		uint64 sequence = wormhole().publishMessage{value: msg.value}(nonce, encoded, finality());
		
		emit bridgeOutEvent(
			payload.tokenID,
			payload.tokenChain,
			payload.toChain,
			addressToBytes(ownerOf(tokenId)),
			recipient
		);
		
		burn(tokenId);
		
		return sequence;
	}
	
	function bridgeIn(bytes calldata encodedVM) external returns (bytes memory) {
		require(isInitialized() == true, "Not Initialized");
		require(evmChainId() == block.chainid, "unsupported fork");
		
		(IWormhole.VM memory vm, bool valid, string memory reason) = wormhole()
			.parseAndVerifyVM(encodedVM);
		require(valid, reason);
		require(
			bytesToAddress(vm.emitterAddress) == address(this) ||
			tokenContracts(vm.emitterChainId) == vm.emitterAddress,
			"Invalid Emitter"
		);
		
		require(isTransferCompleted(vm.hash) == false, "Already Completed The Transfer");
		setTransferCompleted(vm.hash);
		
		CATERC721Structs.CrossChainPayload memory transfer = decodeTransfer(vm.payload);
		require(transfer.toChain == chainId(), "invalid target chain");
		
		address transferRecipient = bytesToAddress(transfer.toAddress);
		
		_mint(transferRecipient, transfer.tokenID);
		_setTokenURI(transfer.tokenID, transfer.uri);
		
		emit bridgeInEvent(
			transfer.tokenID,
			transfer.tokenChain,
			transfer.toChain,
			transfer.toAddress
		);
		
		return vm.payload;
	}
	
	function mint(address recipient) public onlyOwner {
		require(mintedSupply() < maxSupply(), "MAX SUPPLY REACHED");
		uint256 tokenId = mintedSupply();
		setMintedSupply(mintedSupply() + 1);
		_mint(recipient, tokenId);
	}
}

