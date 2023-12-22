// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;
import "./ERC20Permit.sol";
import "./IStabilityPoolManager.sol";

abstract contract IUToken is UERC20Permit {
	// --- Events ---

	event TroveManagerAddressChanged(address _troveManagerAddress);
	event StabilityPoolAddressChanged(address _newStabilityPoolAddress);
	event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);

	event UTokenBalanceUpdated(address _user, uint256 _amount);

	function emergencyStopMinting(address _asset, bool status) external virtual;

	function mint(address _asset, address _account, uint256 _amount) external virtual;

	function burn(address _account, uint256 _amount) external virtual;

	function sendToPool(address _sender, address poolAddress, uint256 _amount) external virtual;

	function returnFromPool(address poolAddress, address user, uint256 _amount) external virtual;
}

