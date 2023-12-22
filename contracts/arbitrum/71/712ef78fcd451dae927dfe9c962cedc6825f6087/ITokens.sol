// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import { IERC20 } from "./IERC20.sol";

interface IbSect is IERC20 {
	// Sets the price of the lbTokens in underlying tokens
	function setPrice(uint256 price_) external;

	// Mint new bTokens tokens to the specified address
	function mintTo(address to, uint256 amount) external;

	// Convert bTokens to underlying tokens
	function convert(uint256 amount) external;

	// Claim underlying tokens held by the contract
	function claimUnderlying(address to) external;
}

interface IveSect is IERC20 {
	function setVeToken(address veToken_) external;

	function mintTo(address to, uint256 amount) external;

	function convertToLock(uint256 amount) external;

	function addValueToLock(uint256 amount) external;
}

