pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

// SPDX-License-Identifier: MIT

interface IGauge {
	function deposit(uint256 value) external;

	function withdraw(uint256 value) external;
}

