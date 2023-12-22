// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { SolidStateDiamond } from "./SolidStateDiamond.sol";
import { ERC20MetadataStorage } from "./ERC20MetadataStorage.sol";

/// @title TokenProxy
/// @dev The TokenProxy Diamond.
contract TokenProxy is SolidStateDiamond {
    constructor(string memory name, string memory symbol) {
        ERC20MetadataStorage.Layout
            storage metadataLayout = ERC20MetadataStorage.layout();

        metadataLayout.name = name;
        metadataLayout.symbol = symbol;
        metadataLayout.decimals = 18;
    }
}

