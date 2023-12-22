// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./CallLib.sol";

abstract contract WalletExec {
	uint256[50] private __gap;

	/**
	 * @notice this method is used by module to perform any external calls from fun wallet
	 * @dev only a known module is allowed to invoke this method.
	 * @param dest the address of the external contract to be called
	 * @param value the amount of ether to forward
	 * @param data the call data to the external contract
	 * @return result the returned result from external contract call
	 */
	function execFromModule(address dest, uint256 value, bytes calldata data) external payable returns (bytes memory) {
		_requireFromModule();
		return CallLib.exec(dest, value, data);
	}

	/**
	 * @notice this method is used to execute the downstream module
	 * @dev only entrypoint or owner is allowed to invoke this method.
	 * @param dest the address of the module to be called
	 * @param value the amount of ether to forward
	 * @param data the call data to the downstream module
	 */
	function execFromEntryPoint(address dest, uint256 value, bytes calldata data) public virtual {
		_requireFromEntryPoint();
		CallLib.exec(dest, value, data);
	}

	/**
	 * @notice Executes batched operations on a collection of downstream modules.
	 * @dev This function can only be invoked by an owner or user with privilege granted.
	 * @dev Giving a user access to this function is the same as giving them owner access 
	 		as no validation checks are being made on the batched calls.
	 * @param dest An array of the addresses for the modules to be called.
	 * @param value An array of ether amounts to forward to each module.
	 * @param data An array of call data to send to each downstream module.
	 */
	function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata data) public virtual {
		require(msg.sender == address(this), "FW502");
		require(dest.length == value.length && dest.length == data.length, "FW524");
		for (uint8 i = 0; i < dest.length; ++i) {
			CallLib.exec(dest[i], value[i], data[i]);
		}
	}

	function _requireFromModule() internal virtual;

	function _requireFromEntryPoint() internal view virtual;
}

