// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import { Ownable } from "./Ownable.sol";
import { IAddressProvider } from "./IAddressProvider.sol";

// import { IAddressProvider } from "../interfaces/IAddressProvider.sol";
contract AddressProvider is Ownable, IAddressProvider {
	event DAOSet(address indexed dao_);
	event EmergencyAdminSet(address indexed newAddr_);
	event AddressSet(bytes32 id, address indexed newAddr_);

	mapping(bytes32 => address) private _addresses;
	bytes32 private constant DAO = "DAO";
	bytes32 private constant EMERGENCY_ADMIN = "EMERGENCY_ADMIN";
	bytes32 private constant ORACLE_MASTER = "ORACLE_MASTER";

	function getAddress(bytes32 id_) external view returns (address) {
		return _addresses[id_];
	}

	function setAddress(bytes32 id_, address newAddress_) external onlyOwner {
		require(bytes32(id_).length != 0, "AP: ZR INP");
		require(newAddress_ != address(0), "AP: ZR ADDR");
		_addresses[id_] = newAddress_;
		emit AddressSet(id_, newAddress_);
	}

	/// @dev get & set emergency admin
	function getEmergencyAdmin() external view override returns (address) {
		return _addresses[EMERGENCY_ADMIN];
	}

	function setEmergencyAdmin(address emergencyAdmin_) external onlyOwner {
		require(emergencyAdmin_ != address(0), "AP: ZR ADDR");
		_addresses[EMERGENCY_ADMIN] = emergencyAdmin_;
		emit EmergencyAdminSet(emergencyAdmin_);
	}

	/// @dev get & set dao
	function getDAO() external view override returns (address) {
		return _addresses[DAO];
	}

	function setDAO(address dao_) external onlyOwner {
		require(dao_ != address(0), "AP: ZR ADDR");
		_addresses[DAO] = dao_;
		emit DAOSet(dao_);
	}

	/// @dev get & set dao
	function getOracleMaster() external view override returns (address) {
		return _addresses[ORACLE_MASTER];
	}

	function setOracleMaster(address newAddr_) external onlyOwner {
		require(newAddr_ != address(0), "AP: ZR ADDR");
		_addresses[ORACLE_MASTER] = newAddr_;
		emit AddressSet(ORACLE_MASTER, newAddr_);
	}
}

