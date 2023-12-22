// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {INFTMetadata} from "./INFTMetadata.sol";
import {IMetadataRouter} from "./IMetadataRouter.sol";

contract NFTMetadataRouter is INFTMetadata {
    address public immutable metadataRouter;

    constructor(address _metadataRouter) {
        metadataRouter = _metadataRouter;
    }

    /// @dev Returns the contract URI for this contract, a modern standard for NFTs
    /// @notice Intended to be invoked in the context of a delegatecall
    function contractURI() public view virtual returns (string memory uri) {
        return IMetadataRouter(metadataRouter).uriOf(_contractRoute(), address(this));
    }

    function _contractRoute() internal pure virtual returns (string memory route) {
        return "contract";
    }

    /*===========
        VIEWS
    ===========*/

    /// @inheritdoc INFTMetadata
    function ext_contractURI() external view returns (string memory uri) {
        return IMetadataRouter(metadataRouter).uriOf("collection", address(this));
    }

    /// @inheritdoc INFTMetadata
    function ext_tokenURI(uint256 tokenId) external view returns (string memory uri) {
        return IMetadataRouter(metadataRouter).tokenURI(address(this), tokenId);
    }
}

