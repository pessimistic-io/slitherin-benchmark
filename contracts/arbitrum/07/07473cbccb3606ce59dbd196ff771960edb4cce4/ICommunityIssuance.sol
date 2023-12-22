// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

interface ICommunityIssuance {
	// --- Events ---

	event PSYTokenAddressSet(address _PSYTokenAddress);
	event StabilityPoolAddressSet(address _stabilityPoolAddress);
	event TotalPSYIssuedUpdated(address indexed stabilityPool, uint256 _totalPSYIssued);

	// --- Functions ---

	function setAddresses(
		address _PSYTokenAddress,
		address _stabilityPoolAddress,
		address _adminContract
	) external;

	function issuePSY() external returns (uint256);

	function sendPSY(address _account, uint256 _PSYamount) external;

	function addFundToStabilityPool(address _pool, uint256 _assignedSupply) external;

	function addFundToStabilityPoolFrom(
		address _pool,
		uint256 _assignedSupply,
		address _spender
	) external;

	function transferFundToAnotherStabilityPool(
		address _target,
		address _receiver,
		uint256 _quantity
	) external;

	function setWeeklyPSYDistribution(address _stabilityPool, uint256 _weeklyReward) external;
}

