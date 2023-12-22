// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Contract imports
import { SolidStateERC721 } from "./SolidStateERC721.sol";
import { IERC721Metadata } from "./IERC721Metadata.sol";
import { ERC721Metadata } from "./ERC721Metadata.sol";

// Storage imports
import { WithModifiers } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";
import { ERC721MetadataStorage } from "./ERC721MetadataStorage.sol";
import { ERC721BaseStorage } from "./ERC721BaseStorage.sol";

contract WLLandFacet is WithModifiers, SolidStateERC721 {
    using ERC721BaseStorage for ERC721BaseStorage.Layout;

    /**
     * @dev Get the token URI for a Wasteland
     */
    function tokenURI(
        uint256 tokenId
    ) external view virtual override(ERC721Metadata, IERC721Metadata) returns (string memory) {
        if (!ERC721BaseStorage.layout().exists(tokenId)) revert Errors.TokenDoesNotExist();
        return string(abi.encodePacked(super._tokenURI(tokenId), ws().landMetadataExtension));
    }

    /**
     * @dev Get the contact URI of Wastelands (used for collection metadata)
     */
    function contractURI() external view returns (string memory) {
        return ws().landContractURI;
    }
}

