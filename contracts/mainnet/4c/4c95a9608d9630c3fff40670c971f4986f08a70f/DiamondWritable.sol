// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import { OwnableInternal } from "./OwnableInternal.sol";
import { DiamondBaseStorage } from "./DiamondBaseStorage.sol";
import { IDiamondWritable } from "./IDiamondWritable.sol";
import { DiamondWritableInternal } from "./DiamondWritableInternal.sol";

/**
 * @title EIP-2535 "Diamond" proxy update contract
 */
abstract contract DiamondWritable is
    IDiamondWritable,
    DiamondWritableInternal,
    OwnableInternal
{
    using DiamondBaseStorage for DiamondBaseStorage.Layout;

    /**
     * @inheritdoc IDiamondWritable
     */
    function diamondCut(
        FacetCut[] calldata facetCuts,
        address target,
        bytes calldata data
    ) external onlyOwner {
        _diamondCut(facetCuts, target, data);
    }
}

