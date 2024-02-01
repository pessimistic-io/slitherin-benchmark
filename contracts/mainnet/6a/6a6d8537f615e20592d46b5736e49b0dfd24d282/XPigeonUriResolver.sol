// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IJBTokenUriResolver } from "./IJBTokenUriResolver.sol";
import {Base64} from "./base64.sol";
import { Ownable } from "./Ownable.sol";
import "./Strings.sol";

contract XPigeonUriResolver is Ownable, IJBTokenUriResolver {
    using Strings for uint256;

    string internal baseUriAsset;
    string internal extension;

    constructor(string memory _baseUriAsset, string memory _extension) {
        baseUriAsset = _baseUriAsset;
        extension = _extension;
    }

    function getUri(uint256 _tokenId) external view returns (string memory tokenUri) {
        string memory json = Base64.encode(bytes(string(abi.encodePacked(
            '{"description":"AI Generated Exhausted Pigeons.","name":"Exhausted Pigeons","externalLink":"https://www.exhausted-pigeon.xyz","image":"',
            baseUriAsset,
            _tokenId.toString(),
            extension,
            '","attributes":[{"trait_type":"Min. Contribution","value":0.01},{"trait_type":"Max. Supply"},{"trait_type":"tier","value":1}]}'))));

        tokenUri = string(abi.encodePacked('data:application/json;base64,', json));
    }

    function setBaseURI(string calldata _baseUriAsset, string calldata _extension) external onlyOwner {
        baseUriAsset = _baseUriAsset;
        extension = _extension;
    }
}

