//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

/**
    Squares interface.
 */
interface ISquare {
	function adminSafeTransferFrom(address _from,
								   address _to,
								   uint256 _tokenId) external;

	function areSquaresFilled() 
		external 
		view 
		returns (bool);
}
