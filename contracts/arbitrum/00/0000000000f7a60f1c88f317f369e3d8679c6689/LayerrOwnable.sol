// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {AddressValue} from "./StorageTypes.sol";
import {IOwnable} from "./IOwnable.sol";
import {LAYERROWNABLE_OWNER_SLOT, LAYERROWNABLE_NEW_OWNER_SLOT} from "./LayerrStorage.sol";

/**
 * @title LayerrOwnable
 * @author 0xth0mas (Layerr)
 * @notice ERC173 compliant ownership interface with two-step transfer/acceptance.
 * @dev LayerrOwnable uses two custom storage slots for current contract owner and new owner as defined in LayerrStorage.
 */
contract LayerrOwnable is IOwnable {
    modifier onlyOwner() {
        if (msg.sender != _getOwner()) {
            revert NotContractOwner();
        }
        _;
    }

    modifier onlyNewOwner() {
        if (msg.sender != _getNewOwner()) {
            revert NotContractOwner();
        }
        _;
    }

    /**
     * @notice Returns the current contract owner
     */
    function owner() external view returns(address _owner) {
        _owner = _getOwner();
    }

    /**
     * @notice Begins first step of ownership transfer. _newOwner will need to call acceptTransfer() to complete.
     * @param _newOwner address to transfer ownership of contract to
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        _setNewOwner(_newOwner);
    }

    /**
     * @notice Second step of ownership transfer called by the new contract owner.
     */
    function acceptTransfer() external onlyNewOwner {
        address _previousOwner = _getOwner();

        //set contract owner to new owner, clear out the newOwner value
        _setOwner(_getNewOwner());
        _setNewOwner(address(0));

        emit OwnershipTransferred(_previousOwner, _getOwner());
    }

    /**
     * @notice Cancels ownership transfer to newOwner before the transfer is accepted.
     */
    function cancelTransfer() external onlyOwner {
        _setNewOwner(address(0));
    }

    /**
     * @notice EIP165 supportsInterface for introspection
     */
    function supportsInterface(bytes4 interfaceID) public view virtual returns (bool) {
        return interfaceID == 0x7f5828d0;
    }

    /** INTERNAL FUNCTIONS */

    /**
     * @dev Internal helper function to load custom storage slot address value
     */
    function _getOwner() internal view returns(address _owner) {
        AddressValue storage ownerValue;
        /// @solidity memory-safe-assembly
        assembly {
            ownerValue.slot := LAYERROWNABLE_OWNER_SLOT
        }
        _owner = ownerValue.value;
    }

    /**
     * @dev Internal helper function to set owner address in custom storage slot
     */
    function _setOwner(address _owner) internal {
        AddressValue storage ownerValue;
        /// @solidity memory-safe-assembly
        assembly {
            ownerValue.slot := LAYERROWNABLE_OWNER_SLOT
        }
        ownerValue.value = _owner;
    }

    /**
     * @dev Internal helper function to load custom storage slot address value
     */
    function _getNewOwner() internal view returns(address _newOwner) {
        AddressValue storage newOwnerValue;
        /// @solidity memory-safe-assembly
        assembly {
            newOwnerValue.slot := LAYERROWNABLE_NEW_OWNER_SLOT
        }
        _newOwner = newOwnerValue.value;
    }

    /**
     * @dev Internal helper function to set new owner address in custom storage slot
     */
    function _setNewOwner(address _newOwner) internal {
        AddressValue storage newOwnerValue;
        /// @solidity memory-safe-assembly
        assembly {
            newOwnerValue.slot := LAYERROWNABLE_NEW_OWNER_SLOT
        }
        newOwnerValue.value = _newOwner;
    }

}
