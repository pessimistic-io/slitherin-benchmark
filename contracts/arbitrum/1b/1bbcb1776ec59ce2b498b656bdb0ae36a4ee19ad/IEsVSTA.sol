// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

import "./EsVSTAModel.sol";

interface IEsVSTA {
	error Unauthorized();

	event EsVSTAMinted(uint256 _amount);
	event UpdateVestingDetails(
		address indexed _user,
		uint256 _amountAdded,
		uint256 startDate,
		uint256 duration
	);
	event FinishVesting(address indexed _user);
	event ClaimVSTA(address indexed _user, uint256 _amount);

	function setHandler(address _handler, bool _isActive) external;

	function setVestingDuration(uint128 _vestingDuration) external;

	function convertVSTAToEsVSTA(uint128 _amount) external;

	function vestEsVSTA(uint128 _amount) external;

	function claimVSTA() external;

	function claimableVSTA() external view returns (uint256 amountClaimable_);

	function getVestingDetails(address _user)
		external
		view
		returns (VestingDetails memory);

	function getUserVestedAmount(address _user) external view returns (uint256);

	function getUserVestedAmountClaimed(address _user) external view returns (uint256);

	function getUserVestingStartDate(address _user) external view returns (uint128);

	function getUserVestingDuration(address _user) external view returns (uint128);
}


