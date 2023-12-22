// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./IModule.sol";
import "./FunWallet.sol";

/**
 * @dev Basic module contract that can be attached to a FunWallet.
 */
abstract contract Module is IModule {
	bytes public constant EMPTY_STATE = bytes("EMPTY_STATE");

	/**
	 * @dev Executes an operation in the context of the module contract.
	 */
	function execute(bytes calldata) external virtual override {
		require(false, "FW100");
	}

	/**
	 * @dev Returns the current state of the module contract.
	 * @param key The key of the state to return.
	 * @return state The current state of the module contract.
	 */
	function getState(bytes32 key) public view returns (bytes memory state) {
		bytes32 moduleKey = HashLib.hash2(key, address(this));
		return FunWallet(payable(msg.sender)).getState(moduleKey);
	}

	function _setState(bytes32 key, bytes memory val) internal {
		FunWallet(payable(msg.sender)).setState(key, val);
	}

	/**
	 * @dev Executes an operation from the context of the FunWallet contract.
	 * @param dest The destination address to execute the operation on.
	 * @param value The value to send with the transaction.
	 * @param data The data to be executed.
	 * @return The return data of the executed operation.
	 */
	function _executeFromFunWallet(address dest, uint256 value, bytes memory data) internal returns (bytes memory) {
		return FunWallet(payable(msg.sender)).execFromModule(dest, value, data);
	}

	function payFee() public virtual {}
}

