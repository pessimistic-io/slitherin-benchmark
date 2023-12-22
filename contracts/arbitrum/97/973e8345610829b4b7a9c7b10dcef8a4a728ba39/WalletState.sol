// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./IEntryPoint.sol";
import "./IWalletState.sol";
import "./HashLib.sol";

abstract contract WalletState is IWalletState {
	IEntryPoint internal _entryPoint;
	// it is publicly readable but only modifiable by the module contract itself
	mapping(bytes32 => bytes) internal moduleState;
	uint256[50] private __gap;

	/**
	 * Get the stored state of a module
	 * @param key the key a module would like to get
	 */
	function getState(bytes32 key) public view returns (bytes memory) {
		return moduleState[key];
	}

	/**
	 * Set the stored state of a module
	 * @param key the key a module would like to store
	 * @param val the value a module would like to store
	 */
	function _setState(bytes32 key, bytes calldata val) internal {
		key = HashLib.hash2(key, msg.sender);
		moduleState[key] = val;
	}

	/**
	 * Get the stored 32 bytes word of a module
	 * @param key the key a module would like to get
	 */
	function getState32(bytes32 key) public view returns (bytes32 out) {
		assembly {
			out := sload(key)
		}
	}

	/**
	 * Get the stored 32 bytes word of a specific module
	 * @param key the key a module would like to get
	 */
	function getState32WithAddr(bytes32 key, address addr) public view returns (bytes32 out) {
		key = HashLib.hash2(key, addr);
		assembly {
			out := sload(key)
		}
	}

	/**
	 * Set the stored 32 bytes word of a module
	 * @param key the key a module would like to store
	 * @param val the value a module would like to store
	 */
	function _setState32(bytes32 key, bytes32 val) internal {
		key = HashLib.hash2(key, msg.sender);
		assembly {
			sstore(key, val)
		}
	}

	function setState(bytes32, bytes calldata) public virtual {
		revert("MUST OVERRIDE");
	}

	function setState32(bytes32, bytes32) public virtual {
		revert("MUST OVERRIDE");
	}
}

