// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IBaseMetadata} from "./IBaseMetadata.sol";

/// @title TokenTypesV1
/// @author Rohan Kulkarni
/// @notice The Token custom data types
interface TokenTypesV1 {
    /// @notice The settings type
    /// @param auction The DAO auction house
    /// @param totalSupply The number of active tokens
    /// @param metadatarenderer The token metadata renderer
    /// @param mintCount The number of minted tokens
    struct Settings {
        address auction;
        uint88 totalSupply;
        IBaseMetadata metadataRenderer;
        uint88 mintCount;
        address treasury;
    }
}

