// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;

import { BeaconManager } from "./BeaconManager.sol";

abstract contract InterfaceManager is BeaconManager {
    bytes32 internal constant INTERFACE_EDITOR = keccak256("INTERFACE_EDITOR");

    error IncorrectArrayLengths(
        uint256 selectorLength,
        uint256 isImplementedLength
    );

    /**
     * @dev mapping beacon name => function selector => isImplemented
     */
    mapping(string => mapping(bytes4 => bool)) public interfaceImplementations;

    /**
     * @dev add interface info to given beacon
     */
    function updateInterfaceImplementations(
        string calldata beaconName,
        bytes4[] calldata selectors,
        bool[] calldata isImplemented
    ) external onlyRole(INTERFACE_EDITOR) {
        // Require that array lengths match
        if (selectors.length != isImplemented.length) {
            revert IncorrectArrayLengths(
                selectors.length,
                isImplemented.length
            );
        }

        // Set
        for (uint256 i; i != selectors.length; ++i) {
            interfaceImplementations[beaconName][selectors[i]] = isImplemented[
                i
            ];
        }
    }

    /**
     * @dev check whether msg.sender supports a given interface id. Used to support ERC165 from a central location.
     * @param interfaceId the interface id to check
     */
    function doISupportInterface(bytes4 interfaceId)
        external
        view
        returns (bool)
    {
        string memory beaconOfSender = beaconTypes[msg.sender];
        return interfaceImplementations[beaconOfSender][interfaceId];
    }
}

