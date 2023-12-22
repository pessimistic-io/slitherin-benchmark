// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IBorrowerOperations {
	function mint(address _to, uint256 _amount) external;

	function burn(address _from, uint256 _amount) external;
}


