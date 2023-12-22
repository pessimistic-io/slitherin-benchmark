// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISFTMintableDelegate {
    function createSlot(bytes calldata inputSlotInfo) external returns (uint256 slot);
	function mint(address mintTo, uint256 slot, uint256 value) external payable returns (uint256 tokenId);
}
