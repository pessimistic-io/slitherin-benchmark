// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
// EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535

// A loupe is a small magnifying glass used to look at diamonds.
// These functions look at diamonds
interface IDiamondLoupe {
    /// These functions are expected to be called frequently
    /// by tools.

    struct Beacon {
        address beaconAddress;
        bytes4[] functionSelectors;
    }

    /// @notice Gets all beacon addresses and their four byte function selectors.
    /// @return beacons_ Beacon
    function beacons() external view returns (Beacon[] memory beacons_);

    /// @notice Gets all the function selectors supported by a specific beacon.
    /// @param _beacon The beacon address.
    /// @return beaconFunctionSelectors_
    function beaconFunctionSelectors(address _beacon)
        external
        view
        returns (bytes4[] memory beaconFunctionSelectors_);

    /// @notice Get all the beacon addresses used by a diamond.
    /// @return beaconAddresses_
    function beaconAddresses() external view returns (address[] memory beaconAddresses_);

    /// @notice Gets the beacon that supports the given selector.
    /// @dev If beacon is not found return address(0).
    /// @param _functionSelector The function selector.
    /// @return beaconAddress_ The beacon address.
    function beaconAddress(bytes4 _functionSelector) external view returns (address beaconAddress_);
}

