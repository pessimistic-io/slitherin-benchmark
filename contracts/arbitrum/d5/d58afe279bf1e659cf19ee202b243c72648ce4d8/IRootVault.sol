// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "./IERC20Metadata.sol";

interface IRootVault is IERC20Metadata
{
	event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

	event Withdraw(
		address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
	);

	function asset() external view returns (address);

	function redeem(uint256 shares, address receiver) external returns (uint256 assets);

	function recomputePricePerTokenAndHarvestFee() external;
}

