// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {OwnableInternal} from "./OwnableInternal.sol";
import {ScapesMetadataStorage} from "./ScapesMetadataStorage.sol";
import {ScapesERC721MetadataStorage} from "./ScapesERC721MetadataStorage.sol";

/**
 * @title Metadata internal functions
 */
contract ScapesMetadataWrite is OwnableInternal {
    /// @dev Store scape DNA that encodes scape attributes and dates.
    function storeDNA(uint256 offset, uint256[] calldata traits)
        external
        onlyOwner
    {
        ScapesMetadataStorage.Layout storage d = ScapesMetadataStorage.layout();
        for (uint256 idx = 0; idx < traits.length; idx++) {
            d.scapeData[offset + idx] = traits[idx];
        }
    }

    /// @dev Store scape DNA that encodes scape attributes and dates.
    function storeTraits(
        string[] calldata names,
        ScapesMetadataStorage.Trait[] calldata traits
    ) external onlyOwner {
        ScapesMetadataStorage.Layout storage d = ScapesMetadataStorage.layout();
        for (uint256 idx = 0; idx < traits.length; idx++) {
            d.traitNames[idx] = names[idx];
            d.traits[names[idx]] = traits[idx];
        }
    }

    /// @dev Store scape DNA that encodes scape attributes and dates.
    function storeVariationNames(
        string[] calldata oldNames,
        string[] calldata newNames
    ) external onlyOwner {
        ScapesMetadataStorage.Layout storage d = ScapesMetadataStorage.layout();
        for (uint256 idx = 0; idx < oldNames.length; idx++) {
            d.variationNames[oldNames[idx]] = newNames[idx];
        }
    }

    /// @dev Store trait offsets.
    function storeOffsets(
        string[] calldata landmarks,
        int256[][] calldata singleOffsets,
        int256[][] calldata doubleOffsets
    ) external onlyOwner {
        ScapesMetadataStorage.Layout storage d = ScapesMetadataStorage.layout();
        for (uint256 index = 0; index < landmarks.length; index++) {
            d.landmarkOffsets[landmarks[index]][1] = singleOffsets[index];
            d.landmarkOffsets[landmarks[index]][2] = doubleOffsets[index];
        }
    }

    function setDescription(string calldata description) external onlyOwner {
        ScapesERC721MetadataStorage.Layout
            storage d = ScapesERC721MetadataStorage.layout();
        d.description = description;
    }

    function setExternalBaseURI(string calldata baseURI) external onlyOwner {
        ScapesERC721MetadataStorage.Layout
            storage d = ScapesERC721MetadataStorage.layout();
        d.externalBaseURI = baseURI;
    }
}

