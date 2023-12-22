// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IStableCoin {
	event EmergencyStopMintingCollateral(address indexed _asset, bool state);
	event MintBurnAccessChanged(address indexed _address, bool state);
	event TransferOwnership(address indexed newOwner);

	error NoAccess();
	error NotOwner();
	error MintingBlocked();

	function owner() external view returns (address);

	function setOwner(address _newOwner) external;

	function setMintBurnAccess(address _address, bool _status) external;

	function emergencyStopMinting(address _asset, bool _status) external;

	function mintDebt(
		address _asset,
		address _account,
		uint256 _amount
	) external;

	function mint(address _account, uint256 _amount) external;

	function burn(address _account, uint256 _amount) external;

	function isCollateralStopFromMinting(address _token) external view returns (bool);

	function hasMintAndBurnPermission(address _address) external view returns (bool);
}

