// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC165.sol";

abstract contract UsingERC165Internal is IERC165 {
	/// @inheritdoc IERC165
	function supportsInterface(bytes4) public view virtual returns (bool) {
		return false;
	}
}

