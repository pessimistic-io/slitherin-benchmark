// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ICATERC721 {
	function initialize(
		uint16 chainId,
		address wormhole,
		uint8 finality,
		uint256 maxSupply,
		string memory base_uri
	) external;
	
	function tokenURI(uint256 tokenId) external view returns (string memory);
	
	function onERC721Received(
		address operator,
		address from,
		uint256 tokenId,
		bytes calldata data
	) external pure returns (bytes4);
	
	function bridgeOut(
		uint256 tokenId,
		uint16 _wormholeChainId,
		bytes32 recipient,
		uint32 nonce
	) external payable returns (uint64);
	
	function bridgeIn(bytes calldata encodedVM) external returns (bytes memory);
	
	function mint(address recipient, string memory _tokenUri) external;
}

