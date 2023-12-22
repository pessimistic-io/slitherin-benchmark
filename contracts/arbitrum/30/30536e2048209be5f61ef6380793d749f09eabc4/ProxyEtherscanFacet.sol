// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { WithOwnership } from "./LibOwnership.sol";
import { LibDiamond } from "./LibDiamond.sol";

import { StorageSlot } from "./StorageSlot.sol";

contract ProxyEtherscanFacet is WithOwnership {
  bytes32 constant IMPLEMENTATION_SLOT =
    bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
  event Upgraded(address indexed implementation);

  function implementation() public view returns (address) {
    return _getImplementation();
  }

  /**
   * @dev Returns the current implementation address.
   */
  function _getImplementation() internal view returns (address) {
    return StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value;
  }

  /**
   * @dev Stores a new address in the EIP1967 implementation slot.
   */
  function _setImplementation(address newImplementation) private {
    LibDiamond.enforceHasContractCode(newImplementation);
    StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value = newImplementation;
    emit Upgraded(newImplementation);
  }

  /**
   * @dev Perform implementation upgrade
   *
   * Emits an {Upgraded} event.
   */

  function setImplementation(address newImplementation) external onlyOwner {
    _setImplementation(newImplementation);
  }
}

