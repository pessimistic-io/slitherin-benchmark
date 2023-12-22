// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

/// @title IERC1155MetadataExtension
/// @dev ERC1155MetadataExtension interface
interface IERC1155MetadataExtension {
    /// @notice reads the ERC1155 collection name
    /// @return name ERC1155 collection name
    function name() external view returns (string memory name);

    /// @notice reads the ERC1155 collection symbol
    /// @return symbol ERC1155 collection symbol
    function symbol() external view returns (string memory symbol);
}

