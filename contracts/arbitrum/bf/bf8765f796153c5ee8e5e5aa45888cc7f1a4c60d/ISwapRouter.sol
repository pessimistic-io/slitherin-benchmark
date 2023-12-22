// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

interface ISwapRouter {
	function swap(
		address[] memory _path,
		uint256 _amountIn,
		uint256 _minOut,
		address _receiver
	) external;
}

