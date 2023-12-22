// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeMathUpgradeable.sol";


/// @title  ExtendedMathLib
/// @notice Library for calculating the square root

library ExtendedMathLib {

	using SafeMathUpgradeable for uint256;

	/// @notice Calculates root
	/// @param  y number
	/// @return z calculated number
	function sqrt(uint y) internal pure returns (uint z) {
		if (y > 3) {
			z = y;
			uint x = y / 2 + 1;
			while (x < z) {
				z = x;
				x = (y / x + x) / 2;
			}
		} else if (y != 0) {
			z = 1;
		}
		return z;
	}
}

