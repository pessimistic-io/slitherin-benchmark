// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.15;

/// @title Safe casting methods
/// @notice Contains methods for safely casting between types
library SafeCast {
	error SafeCastError();

	/// @notice Cast a uint256 to a int256, revert on overflow
	/// @param y The uint256 to be casted
	/// @return z The casted integer, now type int256
	function toInt256(uint256 y) internal pure returns (int256 z) {
		if (y >= 2**255) {
			revert SafeCastError();
		}
		z = int256(y);
	}

	/// @notice Cast a int256 to a uint256, revert on underflow
	/// @param y The int256 to be casted
	/// @return z The casted integer, now type uint256
	function toUint256(int256 y) internal pure returns (uint256 z) {
		if (y < 0) {
			revert SafeCastError();
		}
		z = uint256(y);
	}
}

