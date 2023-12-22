// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { MetaTxFacetStorage } from "./MetaTxFacetStorage.sol";

/// @title Library for handling meta transactions with the EIP2771 standard
/// @notice The logic for getting msgSender and msgData are were copied from OpenZeppelin's
///  ERC2771ContextUpgradeable contract
library LibMeta {
    struct Layout {
        address trustedForwarder;
    }

    bytes32 internal constant FACET_STORAGE_POSITION = keccak256("spellcaster.storage.metatx");

    function layout() internal pure returns (Layout storage l_) {
        bytes32 _position = FACET_STORAGE_POSITION;
        assembly {
            l_.slot := _position
        }
    }

    // =============================================================
    //                      State Helpers
    // =============================================================

    function isTrustedForwarder(address _forwarder) internal view returns (bool isTrustedForwarder_) {
        isTrustedForwarder_ = layout().trustedForwarder == _forwarder;
    }

    // =============================================================
    //                      Meta Tx Helpers
    // =============================================================

    /**
     * @dev The only valid forwarding contract is the one that is going to run the executing function
     */
    function _msgSender() internal view returns (address sender_) {
        if (msg.sender == address(this)) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            /// @solidity memory-safe-assembly
            assembly {
                sender_ := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            sender_ = msg.sender;
        }
    }

    /**
     * @dev The only valid forwarding contract is the one that is going to run the executing function
     */
    function _msgData() internal view returns (bytes calldata data_) {
        if (msg.sender == address(this)) {
            data_ = msg.data[:msg.data.length - 20];
        } else {
            data_ = msg.data;
        }
    }

    function getMetaDelegateAddress() internal view returns (address delegateAddress_) {
        return address(MetaTxFacetStorage.layout().systemDelegateApprover);
    }
}

