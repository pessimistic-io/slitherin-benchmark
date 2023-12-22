// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IGMXRewardTracker {
	function claimable(address _wallet) external view returns (uint256);

	function tokensPerInterval() external view returns (uint256);

	function totalSupply() external view returns (uint256);
}

