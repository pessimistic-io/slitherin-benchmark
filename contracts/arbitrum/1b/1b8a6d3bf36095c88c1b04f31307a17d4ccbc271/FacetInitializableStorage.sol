// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Storage to track facets in a diamond that have been initialized.
 * Needed to prevent accidental re-initializations
 * Name changed to prevent collision with OZ contracts
 * OZ's Initializable storage handles all of the _initializing state, which isn't facet-specific
 */
library FacetInitializableStorage {
    error AlreadyInitialized(bytes32 facetId);

    struct Layout {
        /*
         * @dev Indicates that the contract/facet has been initialized.
         * bytes32 is the contract/facetId (keccak of the contract name)
         * bool is whether or not the contract/facet has been initialized
         */
        mapping(bytes32 => bool) initialized;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("spellcaster.storage.utils.FacetInitializable");

    function getState() internal pure returns (Layout storage l_) {
        bytes32 _position = STORAGE_SLOT;
        assembly {
            l_.slot := _position
        }
    }

    function isInitialized(bytes32 _facetId) internal view returns (bool isInitialized_) {
        isInitialized_ = getState().initialized[_facetId];
    }
}

