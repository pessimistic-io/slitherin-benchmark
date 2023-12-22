// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISFTMintableConcrete {
    function createSlotOnlyDelegate(address txSender, bytes calldata inputSlotInfo) external returns (uint256 slot);
	function mintOnlyDelegate(address txSender, address mintTo, uint256 slot, uint256 tokenId, uint256 value) external;
}
