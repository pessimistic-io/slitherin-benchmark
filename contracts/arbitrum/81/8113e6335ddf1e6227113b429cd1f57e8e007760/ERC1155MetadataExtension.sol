// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { ERC1155MetadataExtensionInternal } from "./ERC1155MetadataExtensionInternal.sol";
import { IERC1155MetadataExtension } from "./IERC1155MetadataExtension.sol";

/// @title ERC1155MetadataExtension
/// @dev ERC1155MetadataExtension contract
abstract contract ERC1155MetadataExtension is
    ERC1155MetadataExtensionInternal,
    IERC1155MetadataExtension
{
    /// @inheritdoc IERC1155MetadataExtension
    function name() external view virtual returns (string memory) {
        return _name();
    }

    /// @inheritdoc IERC1155MetadataExtension
    function symbol() external view virtual returns (string memory) {
        return _symbol();
    }
}

