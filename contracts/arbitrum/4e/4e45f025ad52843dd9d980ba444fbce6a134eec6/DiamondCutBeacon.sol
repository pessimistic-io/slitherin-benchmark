// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
// EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535

import {IDiamondCut, IDiamond} from "./IDiamondCut.sol";
import {LibDiamond} from "./LibDiamond.sol";

// Remember to add the loupe functions from DiamondLoupeBeacon to the diamond.
// The loupe functions are required by the EIP2535 Diamonds standard

contract DiamondCutBeacon is IDiamondCut {
    /// @notice Add/replace/remove any number of functions and optionally execute
    ///         a function with delegatecall
    /// @param _diamondCut Contains the beacon addresses and function selectors
    /// @param _init The address of the contract or beacon to execute _calldata
    /// @param _calldata A function call, including function selector and arguments
    ///                  _calldata is executed with delegatecall on _init
    function diamondCut(IDiamond.BeaconCut[] calldata _diamondCut, address _init, bytes calldata _calldata)
        external
        override
    {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}

