// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

interface ICommunityIssuance {
	// --- Events ---

	event YOUTokenAddressSet(address _YOUTokenAddress);
	event StabilityPoolAddressSet(address _stabilityPoolAddress);
	event TotalYOUIssuedUpdated(address indexed stabilityPool, uint256 _totalYOUIssued);

	// --- Functions ---

	function setAddresses(
		address _YOUTokenAddress,
		address _stabilityPoolAddress,
		address _adminContract
	) external;

	function issueYOU() external returns (uint256);

	function sendYOU(address _account, uint256 _YOUamount) external;

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

	function setWeeklyYouDistribution(address _stabilityPool, uint256 _weeklyReward) external;
}

