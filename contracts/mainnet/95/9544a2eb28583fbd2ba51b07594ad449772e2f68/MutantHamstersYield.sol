// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC721A.sol";
import "./MutantHamstersToken.sol";


abstract contract MutantHamstersYield is ERC721A, Ownable{
    MutantHamstersToken public yieldToken;

	function setYieldToken(address _yield) external onlyOwner {
		yieldToken = MutantHamstersToken(_yield);
	}

	function getReward() external {
		yieldToken.updateReward(msg.sender, address(0));
		yieldToken.getReward(msg.sender);
	}

	function transferFrom(address from, address to, uint256 tokenId) public override {
		ERC721A.transferFrom(from, to, tokenId);
		yieldToken.updateReward(from, to);
	}

	function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public override {
		ERC721A.safeTransferFrom(from, to, tokenId, _data);
		yieldToken.updateReward(from, to);
	}
}
