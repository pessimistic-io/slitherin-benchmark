// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

interface IWalletState {
	/**
	 * @dev Returns the current state of the module contract.
	 * @param key The key of the state to return.
	 * @return state The current state of the module contract.
	 */
	function getState(bytes32 key) external view returns (bytes memory);

	/**
	 * Get the stored 32 bytes word of a module
	 * @param key the key a module would like to get
	 */
	function getState32(bytes32 key) external view returns (bytes32 out);

	/**
	 * Set the stored state of a module
	 * @param key the key a module would like to store
	 * @param val the value a module would like to store
	 */
	function setState(bytes32 key, bytes calldata val) external;

	/**
	 * Set the stored 32 bytes word of a module
	 * @param key the key a module would like to store
	 * @param val the value a module would like to store
	 */
	function setState32(bytes32 key, bytes32 val) external;
}

