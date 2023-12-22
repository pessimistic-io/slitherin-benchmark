// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { SolidStateDiamond } from "./SolidStateDiamond.sol";

import { ERC1155MetadataExtensionStorage } from "./ERC1155MetadataExtensionStorage.sol";
import { PerpetualMintStorage } from "./Storage.sol";

/// @title Core
/// @dev The Core Diamond.
contract Core is SolidStateDiamond {
    constructor(
        address mintToken,
        string memory receiptName,
        string memory receiptSymbol
    ) {
        ERC1155MetadataExtensionStorage.Layout
            storage metadataExtensionLayout = ERC1155MetadataExtensionStorage
                .layout();

        PerpetualMintStorage.layout().mintToken = mintToken;

        metadataExtensionLayout.name = receiptName;

        metadataExtensionLayout.symbol = receiptSymbol;
    }
}

