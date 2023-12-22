// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

interface IAddressProvider {
	function getDAO() external view returns (address);

	function getOracleMaster() external view returns (address);

	function getEmergencyAdmin() external view returns (address);
}

