// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IERC20.sol";

interface IMozToken is IERC20{
	function lockAndVestAndTransfer(
			address walletAddress, 
			uint256 amount, 
			uint256 lockStart,
			uint256 lockPeriod,
			uint256 vestPeriod
		)  external returns (bool);
	function multipleLockAndVestAndTransfer(address[] memory walletAddresses, 
			uint256[] memory amounts, 
			uint256 lockStart,	
			uint256 lockPeriod, 
			uint256 vestPeriod
		)  external returns (bool);
	function burn(uint256 amount, address from) external;
	function mint(uint256 amount, address to) external;
}
