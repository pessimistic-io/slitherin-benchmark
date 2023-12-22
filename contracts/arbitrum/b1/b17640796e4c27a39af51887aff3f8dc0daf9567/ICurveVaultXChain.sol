// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICurveVaultXChain {
	function deposit(address _staker, uint256 _amount) external;

	function withdraw(uint256 _shares) external;

	function init(
		address _token, 
		string memory name_, 
		string memory symbol_, 
		address _registry,
		address _gauge
	) external;
}

