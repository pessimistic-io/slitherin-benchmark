// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Proxy} from "./Proxy.sol";
import {StorageSlot} from "./StorageSlot.sol";
import {Ownable} from "./Ownable.sol";

/// @title Task Creator for Supa Automations
contract TaskCreatorProxy is Proxy, Ownable {

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor() {
        _transferOwnership(tx.origin);
    }

    function upgrade(address implementation_) external onlyOwner {
        StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = implementation_;
    }

    function implementation() external view returns (address) {
        return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    function _setImplementation(address newImplementation) private {
        StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    function _implementation() internal view override returns (address) {
        return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }
}

