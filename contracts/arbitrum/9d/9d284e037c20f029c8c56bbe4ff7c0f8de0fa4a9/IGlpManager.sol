pragma solidity 0.8.17;

// SPDX-License-Identifier: MIT

interface IGlpManager
{
	function getPrice(bool _maximise) external view returns (uint256);
}

