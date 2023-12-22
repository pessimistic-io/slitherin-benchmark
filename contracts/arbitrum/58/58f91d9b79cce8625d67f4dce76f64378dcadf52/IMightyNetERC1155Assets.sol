// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC1155Upgradeable.sol";

interface IMightyNetERC1155Assets is IERC1155Upgradeable {
	// ------------------------------
	// 			 Minting (Receive)
	// ------------------------------

	function mintBatch(
		address to,
		uint256[] memory ids,
		uint256[] memory amounts
	) external;

	// ------------------------------
	// 			 Burning (Send)
	// ------------------------------

	function burnBatch(
		address from,
		uint256[] memory ids,
		uint256[] memory amounts
	) external;
}

