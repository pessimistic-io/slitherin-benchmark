// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;


import { IDiamondCut } from "./IDiamondCut.sol";
import { LibDiamond } from "./LibDiamond.sol";

// Remember to add the loupe functions from DiamondLoupeFacet to the diamond.
// The loupe functions are required by the EIP2535 Diamonds standard

contract DiamondCutFacet is IDiamondCut {
    /// @notice Add/replace/remove any number of functions and optionally execute
    ///         a function with delegatecall
    /// @param _diamondCut Contains the facet addresses and function selectors
    /// @param _init The address of the contract or facet to execute _calldata
    /// @param _calldata A function call, including function selector and arguments
    ///                  _calldata is executed with delegatecall on _init
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {
                
        require(LibDiamond.hasRole(LibDiamond.getRoleAdmin(LibDiamond.ADMIN),msg.sender));
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}

