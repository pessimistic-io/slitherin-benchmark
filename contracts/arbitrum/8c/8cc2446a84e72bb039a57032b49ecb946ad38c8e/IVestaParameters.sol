// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVestaParameters {
	function MCR(address _collateral) external view returns (uint256);
}


