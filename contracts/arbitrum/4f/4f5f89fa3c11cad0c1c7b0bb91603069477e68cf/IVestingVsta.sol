pragma solidity ^0.8.10;

interface IVestingVsta {
	function addEntityVesting(
		address _entity,
		uint256 _vestingType,
		uint256 _totalSupply
	) external;

	function addEntityVestingWithConfig(
		address _entity,
		uint256 _vestingType,
		uint256 _totalSupply,
		uint256 _initialDateTimestamp,
		uint256 _lockClaimingInSeconds,
		uint256 _vestingDurationInSeconds
	) external;

	function lowerEntityVesting(
		address _entity,
		uint256 _vestingType,
		uint256 _newTotalSupply
	) external;

	function addSupplyToEntityVesting(
		address _entity,
		uint256 _vestingType,
		uint256 _extraSupply
	) external;

	function removeEntityVesting(address _entity, uint256 _vestingType) external;

	function claimVSTAToken(uint256 _vestingType) external;

	function transferUnassignedVSTA() external;

	function getClaimableVSTA(address _entity, uint256 _vestingType)
		external
		view
		returns (uint256 claimable);

	function getUnassignVSTATokensAmount() external view returns (uint256);

	function getEntityVestingTotalSupply(address _entity, uint256 _vestingType)
		external
		view
		returns (uint256);

	function getEntityVestingLeft(address _entity, uint256 _vestingType)
		external
		view
		returns (uint256);

	function isEntityExits(address _entity, uint256 _vestingType)
		external
		view
		returns (bool);
}


