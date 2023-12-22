// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
// EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535

// The functions in DiamondLoupeBeacon MUST be added to a diamond.
// The EIP-2535 Diamond standard requires these functions.

import {LibDiamond} from "./LibDiamond.sol";
import {IDiamondLoupe} from "./IDiamondLoupe.sol";
import {IERC165} from "./IERC165.sol";

contract DiamondLoupeBeacon is IDiamondLoupe, IERC165 {
    // Diamond Loupe Functions
    ////////////////////////////////////////////////////////////////////
    /// These functions are expected to be called frequently by tools.
    //
    // struct Beacon {
    //     address beaconAddress;
    //     bytes4[] functionSelectors;
    // }
    /// @notice Gets all beacons and their selectors.
    /// @return beacons_ Beacon
    function beacons() external view override returns (Beacon[] memory beacons_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 selectorCount = ds.selectors.length;
        // create an array set to the maximum size possible
        beacons_ = new Beacon[](selectorCount);
        // create an array for counting the number of selectors for each beacon
        uint16[] memory numBeaconSelectors = new uint16[](selectorCount);
        // total number of beacons
        uint256 numBeacons;
        // loop through function selectors
        for (uint256 selectorIndex; selectorIndex < selectorCount; selectorIndex++) {
            bytes4 selector = ds.selectors[selectorIndex];
            address beaconAddress_ = ds.beaconAddressAndSelectorPosition[selector].beaconAddress;
            bool continueLoop = false;
            // find the functionSelectors array for selector and add selector to it
            for (uint256 beaconIndex; beaconIndex < numBeacons; beaconIndex++) {
                if (beacons_[beaconIndex].beaconAddress == beaconAddress_) {
                    beacons_[beaconIndex].functionSelectors[numBeaconSelectors[beaconIndex]] = selector;
                    numBeaconSelectors[beaconIndex]++;
                    continueLoop = true;
                    break;
                }
            }
            // if functionSelectors array exists for selector then continue loop
            if (continueLoop) {
                continueLoop = false;
                continue;
            }
            // create a new functionSelectors array for selector
            beacons_[numBeacons].beaconAddress = beaconAddress_;
            beacons_[numBeacons].functionSelectors = new bytes4[](selectorCount);
            beacons_[numBeacons].functionSelectors[0] = selector;
            numBeaconSelectors[numBeacons] = 1;
            numBeacons++;
        }
        for (uint256 beaconIndex; beaconIndex < numBeacons; beaconIndex++) {
            uint256 numSelectors = numBeaconSelectors[beaconIndex];
            bytes4[] memory selectors = beacons_[beaconIndex].functionSelectors;
            // setting the number of selectors
            assembly {
                mstore(selectors, numSelectors)
            }
        }
        // setting the number of beacons
        assembly {
            mstore(beacons_, numBeacons)
        }
    }

    /// @notice Gets all the function selectors supported by a specific beacon.
    /// @param _beacon The beacon address.
    /// @return _beaconFunctionSelectors The selectors associated with a beacon address.
    function beaconFunctionSelectors(address _beacon)
        external
        view
        override
        returns (bytes4[] memory _beaconFunctionSelectors)
    {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 selectorCount = ds.selectors.length;
        uint256 numSelectors;
        _beaconFunctionSelectors = new bytes4[](selectorCount);
        // loop through function selectors
        for (uint256 selectorIndex; selectorIndex < selectorCount; selectorIndex++) {
            bytes4 selector = ds.selectors[selectorIndex];
            address beaconAddress_ = ds.beaconAddressAndSelectorPosition[selector].beaconAddress;
            if (_beacon == beaconAddress_) {
                _beaconFunctionSelectors[numSelectors] = selector;
                numSelectors++;
            }
        }
        // Set the number of selectors in the array
        assembly {
            mstore(_beaconFunctionSelectors, numSelectors)
        }
    }

    /// @notice Get all the beacon addresses used by a diamond.
    /// @return beaconAddresses_
    function beaconAddresses() external view override returns (address[] memory beaconAddresses_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 selectorCount = ds.selectors.length;
        // create an array set to the maximum size possible
        beaconAddresses_ = new address[](selectorCount);
        uint256 numBeacons;
        // loop through function selectors
        for (uint256 selectorIndex; selectorIndex < selectorCount; selectorIndex++) {
            bytes4 selector = ds.selectors[selectorIndex];
            address beaconAddress_ = ds.beaconAddressAndSelectorPosition[selector].beaconAddress;
            bool continueLoop = false;
            // see if we have collected the address already and break out of loop if we have
            for (uint256 beaconIndex; beaconIndex < numBeacons; beaconIndex++) {
                if (beaconAddress_ == beaconAddresses_[beaconIndex]) {
                    continueLoop = true;
                    break;
                }
            }
            // continue loop if we already have the address
            if (continueLoop) {
                continueLoop = false;
                continue;
            }
            // include address
            beaconAddresses_[numBeacons] = beaconAddress_;
            numBeacons++;
        }
        // Set the number of beacon addresses in the array
        assembly {
            mstore(beaconAddresses_, numBeacons)
        }
    }

    /// @notice Gets the beacon address that supports the given selector.
    /// @dev If beacon is not found return address(0).
    /// @param _functionSelector The function selector.
    /// @return beaconAddress_ The beacon address.
    function beaconAddress(bytes4 _functionSelector) external view override returns (address beaconAddress_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        beaconAddress_ = ds.beaconAddressAndSelectorPosition[_functionSelector].beaconAddress;
    }

    // This implements ERC-165.
    function supportsInterface(bytes4 _interfaceId) external view override returns (bool) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.supportedInterfaces[_interfaceId];
    }
}

