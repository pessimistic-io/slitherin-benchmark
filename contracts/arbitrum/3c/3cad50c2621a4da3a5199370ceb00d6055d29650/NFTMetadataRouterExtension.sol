// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Extension} from "./Extension.sol";
import {NFTMetadataRouter} from "./NFTMetadataRouter.sol";

contract NFTMetadataRouterExtension is NFTMetadataRouter, Extension {
    /*=======================
        CONTRACT METADATA
    =======================*/

    constructor(address router) Extension() NFTMetadataRouter(router) {}

    function _contractRoute() internal pure override returns (string memory route) {
        return "extension";
    }

    /*===============
        EXTENSION
    ===============*/

    /// @inheritdoc Extension
    function getAllSelectors() public pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = this.ext_contractURI.selector;
        selectors[1] = this.ext_tokenURI.selector;
        return selectors;
    }

    /// @inheritdoc Extension
    function signatureOf(bytes4 selector) public pure override returns (string memory) {
        if (selector == this.ext_contractURI.selector) {
            return "ext_contractURI()";
        } else if (selector == this.ext_tokenURI.selector) {
            return "ext_tokenURI(uint256)";
        } else {
            return "";
        }
    }
}

