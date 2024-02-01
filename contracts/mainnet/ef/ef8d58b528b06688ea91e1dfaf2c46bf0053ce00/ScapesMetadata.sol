// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {OwnableInternal} from "./OwnableInternal.sol";
import {IERC721BaseInternal} from "./IERC721BaseInternal.sol";
import {Base64} from "./Base64.sol";
import {ScapesMetadataInternal, ScapesMetadataStorage, ScapesERC721MetadataStorage} from "./ScapesMetadataInternal.sol";
import {ScapesMerge} from "./ScapesMerge.sol";
import {ERC721BaseStorage} from "./ERC721BaseStorage.sol";

/// @title ScapesMetadata
/// @author akuti.eth | scapes.eth
/// @notice Adds metadata information to Scapes
/// @dev A facet to add ERC721 metadata extension and additional metadata functions to Scapes
contract ScapesMetadata is
    ScapesMetadataInternal,
    OwnableInternal,
    IERC721BaseInternal
{
    using ERC721BaseStorage for ERC721BaseStorage.Layout;

    /**
     * @notice Get attributes for given Scape
     * @param tokenId token id
     * @return scape struct containing scape attributes
     */
    function getScape(uint256 tokenId)
        external
        view
        returns (ScapesMetadataInternal.Scape memory)
    {
        return _getScape(tokenId, false);
    }

    /**
     * @notice Get image for given token (1-10k scapes, 10k+ merges)
     * @param tokenId token id
     * @return image data uri of an svg image
     */
    function getScapeImage(uint256 tokenId)
        external
        view
        returns (string memory)
    {
        return _getImage(tokenId, true, 0);
    }

    /**
     * @notice Get image for given token (1-10k scapes, 10k+ merges)
     * @param tokenId token id
     * @param base64_ Whether to encode the svg with base64
     * @param scale Image scale multiplier (set to 0 for auto scaling)
     * @return image data uri of an svg image
     */
    function getScapeImage(
        uint256 tokenId,
        bool base64_,
        uint256 scale
    ) external view returns (string memory) {
        return _getImage(tokenId, base64_, scale);
    }

    function convertMergeId(uint256 tokenId)
        external
        pure
        returns (ScapesMerge.Merge memory)
    {
        return ScapesMerge.fromId(tokenId);
    }

    /**
     * @notice Get generated URI for given token
     * @return token URI
     */
    function tokenURI(uint256 tokenId) public view returns (string memory) {
        if (!ERC721BaseStorage.layout().exists(tokenId))
            revert ERC721Base__NonExistentToken();
        return _getJson(tokenId, true);
    }

    /**
     * @notice Get token name
     * @return token name
     */
    function name() public view returns (string memory) {
        return ScapesERC721MetadataStorage.layout().name;
    }

    /**
     * @notice Get token symbol
     * @return token symbol
     */
    function symbol() public view returns (string memory) {
        return ScapesERC721MetadataStorage.layout().symbol;
    }
}

