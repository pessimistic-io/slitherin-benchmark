//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

interface IExploration {

	// Returns minimum staking time in seconds
	function setMinStakingTimeInSeconds(uint256 _minStakingTime) external;

	// Returns address of owner if donkey is staked
	function ownerForStakedDonkey(uint256 _tokenId) external view returns(address);

	// Returns location for donkey
	function locationForStakedDonkey(uint256 _tokenId) external view returns(Location);

	// Total number of staked donkeys for address
	function balanceOf(address _owner) external view returns (uint256);
}

enum Location {
	NOT_STAKED,
	EXPLORATION
}
