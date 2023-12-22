// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IRestrictedRegistry {
	function isRestricted(address tokenContract, uint256 tokenId)
		external
		view
		returns (bool);

	function restrict(address tokenContract, uint256[] calldata tokenIds)
		external;

	function unrestrict(address tokenContract, uint256[] calldata tokenIds)
		external;
}

