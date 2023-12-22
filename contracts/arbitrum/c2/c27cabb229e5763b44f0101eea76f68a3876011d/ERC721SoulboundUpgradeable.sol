// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721PausableUpgradeable.sol";
import "./ERC721BurnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";

error NonTransferrable();

abstract contract ERC721SoulboundUpgradeable is
	ERC721PausableUpgradeable,
	ERC721BurnableUpgradeable,
	OwnableUpgradeable,
	AccessControlUpgradeable,
	ReentrancyGuardUpgradeable
{
	// ------------------------------
	// 			 Approvals
	// ------------------------------
	function approve(
		address, /*to*/
		uint256 /*tokenId*/
	) public virtual override(ERC721Upgradeable) {
		revert NonTransferrable();
	}

	function setApprovalForAll(
		address, /*operator_*/
		bool /*_approved*/
	) public virtual override(ERC721Upgradeable) {
		revert NonTransferrable();
	}

	// ------------------------------
	// 			 Transfers
	// ------------------------------

	function _transfer(
		address, /*from*/
		address, /*to*/
		uint256 /*tokenId*/
	) internal pure override(ERC721Upgradeable) {
		revert NonTransferrable();
	}

	function _beforeTokenTransfer(
		address from,
		address to,
		uint256 tokenId,
		uint256 batchSize
	)
		internal
		virtual
		override(ERC721Upgradeable, ERC721PausableUpgradeable)
		whenNotPaused
	{
		require(
			from == address(0) || to == address(0),
			"This is a soulbound token. It cannot be transferred, only burned"
		);
		super._beforeTokenTransfer(from, to, tokenId, batchSize);
	}

	// ------------------------------
	// 		   Miscellaneous
	// ------------------------------

	function supportsInterface(bytes4 interfaceId)
		public
		view
		virtual
		override(ERC721Upgradeable, AccessControlUpgradeable)
		returns (bool)
	{
		return super.supportsInterface(interfaceId);
	}
}

