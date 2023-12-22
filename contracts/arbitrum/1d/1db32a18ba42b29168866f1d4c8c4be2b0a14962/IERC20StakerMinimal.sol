// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

/// @title IERC20StakerMinimal
/// @author Koala Money
interface IERC20StakerMinimal {
	function token() external view returns (address);

	function balanceOf(address _owner) external view returns (uint256);

	function stake(address _recipient) external returns (uint256);

	function unstake(address _recipient, uint256 _amount) external;
}

