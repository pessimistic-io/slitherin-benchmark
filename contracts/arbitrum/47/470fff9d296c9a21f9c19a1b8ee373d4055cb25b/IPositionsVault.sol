//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IPositionsVault {
	event Put(uint256 indexed tokenId, address indexed owner);
	event Collect(uint256 indexed tokenId, uint256 token0Fees, uint256 token1Fees);
	event Release(uint256 indexed tokenId, address indexed owner);

	function put(uint256 tokenId) external returns (address owner);
	function collect(uint256 tokenId) external returns (uint256 token0Fees, uint256 token1Fees);
	function release(uint256 tokenId) external returns (address owner);
}

