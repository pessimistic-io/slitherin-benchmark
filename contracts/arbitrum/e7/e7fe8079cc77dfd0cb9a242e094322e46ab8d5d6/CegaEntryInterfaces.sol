// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;
/******************************************************************************\
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
/******************************************************************************/

import { ICegaEntryInterfaces } from "./ICegaEntryInterfaces.sol";
import { IERC165 } from "./cega-entry_IERC165.sol";
import { CegaEntryLib } from "./CegaEntryLib.sol";

// The EIP-2535 Diamond standard requires these functions.

contract CegaEntryInterfaces is ICegaEntryInterfaces, IERC165 {
    ////////////////////////////////////////////////////////////////////
    /// These functions are expected to be called frequently by tools.
    // Facet == Implementtion

    /// @notice Gets all facets and their selectors.
    /// @return facets_ Implementation
    function facets()
        external
        view
        override
        returns (Implementation[] memory facets_)
    {
        CegaEntryLib.ProxyStorage storage ds = CegaEntryLib.proxyStorage();
        uint256 numFacets = ds.implementationAddresses.length;
        facets_ = new Implementation[](numFacets);
        for (uint256 i; i < numFacets; i++) {
            address facetAddress_ = ds.implementationAddresses[i];
            facets_[i].implAddress = facetAddress_;
            facets_[i].functionSelectors = ds
                .implementationFunctionSelectors[facetAddress_]
                .functionSelectors;
        }
    }

    /// @notice Gets all the function selectors provided by a facet.
    /// @param _facet The facet address.
    /// @return facetFunctionSelectors_
    function facetFunctionSelectors(
        address _facet
    ) external view override returns (bytes4[] memory facetFunctionSelectors_) {
        CegaEntryLib.ProxyStorage storage ds = CegaEntryLib.proxyStorage();
        facetFunctionSelectors_ = ds
            .implementationFunctionSelectors[_facet]
            .functionSelectors;
    }

    /// @notice Get all the facet addresses used by a diamond.
    /// @return facetAddresses_
    function facetAddresses()
        external
        view
        override
        returns (address[] memory facetAddresses_)
    {
        CegaEntryLib.ProxyStorage storage ds = CegaEntryLib.proxyStorage();
        facetAddresses_ = ds.implementationAddresses;
    }

    /// @notice Gets the facet that supports the given selector.
    /// @dev If facet is not found return address(0).
    /// @param _functionSelector The function selector.
    /// @return facetAddress_ The facet address.
    function facetAddress(
        bytes4 _functionSelector
    ) external view override returns (address facetAddress_) {
        CegaEntryLib.ProxyStorage storage ds = CegaEntryLib.proxyStorage();
        facetAddress_ = ds
            .selectorToImplAndPosition[_functionSelector]
            .implAddress;
    }

    // This implements ERC-165.
    function supportsInterface(
        bytes4 _interfaceId
    ) external view override returns (bool) {
        CegaEntryLib.ProxyStorage storage ds = CegaEntryLib.proxyStorage();

        return (type(ICegaEntryInterfaces).interfaceId == _interfaceId ||
            ds.supportedInterfaces[_interfaceId]);
    }
}

