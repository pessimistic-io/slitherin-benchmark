// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

/// @title IERC20StakerMinimal
/// @author Koala Money
interface IERC20StakerMinimal {
	function balanceOf(address _owner) external view returns (uint256);
}

