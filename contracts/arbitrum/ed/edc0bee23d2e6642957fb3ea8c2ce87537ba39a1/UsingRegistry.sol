// SPDX-License-Identifier: MPL-2.0
pragma solidity =0.8.9;

import "./IAddressRegistry.sol";

/**
 * Module for using AddressRegistry contracts.
 */
abstract contract UsingRegistry {
	address private _registry;

	/**
	 * Initialize the argument as AddressRegistry address.
	 */
	constructor(address _addressRegistry) {
		_registry = _addressRegistry;
	}

	/**
	 * Returns the latest AddressRegistry instance.
	 */
	function registry() internal view returns (IAddressRegistry) {
		return IAddressRegistry(_registry);
	}

	/**
	 * Returns the AddressRegistry address.
	 */
	function registryAddress() external view returns (address) {
		return _registry;
	}
}

