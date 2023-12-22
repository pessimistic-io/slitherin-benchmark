// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

interface IOracle {
	function getPrice(uint256 _amount) external view returns (uint256);

	function decimals() external view returns (uint8);
}

