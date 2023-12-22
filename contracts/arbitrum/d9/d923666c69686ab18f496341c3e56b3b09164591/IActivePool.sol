// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;
import "./IPool.sol";

interface IActivePool is IPool {
	// --- Events ---
	event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
	event TroveManagerAddressChanged(address _newTroveManagerAddress);
	event ActivePoolUDebtUpdated(address _asset, uint256 _UDebt);
	event ActivePoolAssetBalanceUpdated(address _asset, uint256 _balance);

	// --- Functions ---
	function sendAsset(address _asset, address _account, uint256 _amount) external;
}

