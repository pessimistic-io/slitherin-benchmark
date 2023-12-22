// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IOracle {
	function getPrice(address _asset) external view returns (uint256);
}

