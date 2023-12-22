// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

/// @title IControllerZooMinimal
/// @author Koala Money
interface IControllerZooMinimal {
	function controlBeforeDeposit(
		address _zoo,
		address _owner,
		uint256 _amount
	) external;

	function controlBeforeWithdraw(
		address _zoo,
		address _owner,
		uint256 _amount
	) external;

	function controlBeforeMint(
		address _zoo,
		address _owner,
		uint256 _amount
	) external;

	function controlBeforeBurn(
		address _zoo,
		address _owner,
		uint256 _amount
	) external;

	function controlBeforeLiquidate(
		address _zoo,
		address _owner,
		uint256 _amount
	) external;

	function controlAfterDeposit(
		address _zoo,
		address _owner,
		uint256 _amount
	) external;

	function controlAfterWithdraw(
		address _zoo,
		address _owner,
		uint256 _amount
	) external;

	function controlAfterMint(
		address _zoo,
		address _owner,
		uint256 _amount
	) external;

	function controlAfterBurn(
		address _zoo,
		address _owner,
		uint256 _amount
	) external;

	function controlAfterLiquidate(
		address _zoo,
		address _owner,
		uint256 _amount
	) external;
}

