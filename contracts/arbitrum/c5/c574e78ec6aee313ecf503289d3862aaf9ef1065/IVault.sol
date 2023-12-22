pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

// SPDX-License-Identifier: MIT

interface VaultAPI {
	function mint(uint256 mintAmount) external returns (uint256);

	function redeem(uint redeemTokens) external returns (uint256);

	function exchangeRateCurrent() external returns (uint256);

	function transfer(address who, uint256 amount) external returns (bool);

	function increaseMockBalance() external;

	function balanceOf(address who) external view returns (uint256);
}

