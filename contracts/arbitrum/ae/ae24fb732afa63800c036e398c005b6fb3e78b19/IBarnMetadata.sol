//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

interface IBarnMetadata {
	function tokenURI(uint256 _tokenId) external view returns (string memory);

	function setBaseURI(string calldata _baseURI) external;

	function setBarnType(uint256 _tokenId, uint256 _randomNumber) external;

	//May not need if using fallback method
	// function setRequestIdToToken(uint256 _requestId) external;
}

