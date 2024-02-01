// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {MetadataRendererTypesV1} from "./MetadataRendererTypesV1.sol";

/// @title MetadataRendererTypesV1
/// @author Iain Nash & Rohan Kulkarni
/// @notice The Metadata Renderer storage contract
contract MetadataRendererStorageV1 is MetadataRendererTypesV1 {
    /// @notice The metadata renderer settings
    Settings public settings;

    Group[11] public groups;

    /// @notice The attributes generated for a token - mapping of tokenID uint16 array
    /// @dev Array of size 16 1st element [0] used for number of attributes chosen, next N elements for those selections
    /// @dev token ID
    mapping(uint256 => uint16[16]) public attributes;
}

