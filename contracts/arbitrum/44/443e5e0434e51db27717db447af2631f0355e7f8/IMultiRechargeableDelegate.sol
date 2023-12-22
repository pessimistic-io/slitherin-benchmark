// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMultiRechargeableDelegate {
	event Recharge(uint256 indexed slot, address indexed currency, uint256 amount);
	event Claim(address indexed to, uint256 indexed tokenId, address indexed currency, uint256 amount);
	
	function recharge(uint256 slot_, address currency_, uint256 amount_) external payable;
	function claimTo(address to_, uint256 tokenId_, address currency_, uint256 amount_) external;
}
