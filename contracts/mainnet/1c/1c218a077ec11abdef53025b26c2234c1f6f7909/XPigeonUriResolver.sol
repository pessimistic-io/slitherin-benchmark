// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IJBTokenUriResolver } from "./IJBTokenUriResolver.sol";
import { Ownable } from "./Ownable.sol";
import "./Strings.sol";

contract XPigeonUriResolver is Ownable, IJBTokenUriResolver {
    using Strings for uint256;

    string internal ipfsFolder;
    string internal extension;

    constructor(string memory _ipfsFolder, string memory _extension) {
        ipfsFolder = _ipfsFolder;
        extension = _extension;
    }

    function getUri(uint256 _tokenId) external view returns (string memory tokenUri) {
        tokenUri = string.concat(
            '{"description":"AI Generated Exhausted Pigeons.","name":"Exhausted Pigeons","externalLink":"https://www.exhausted-pigeon.xyz","image":"ipfs://',
            ipfsFolder,
            '/',
            _tokenId.toString(),
            extension,
            '","attributes":[{"trait_type":"Min. Contribution","value":0.01},{"trait_type":"Max. Supply"},{"trait_type":"tier","value":1}]}');
    }

    function setBaseURI(string calldata _ipfsFolder, string calldata _extension) external onlyOwner {
        ipfsFolder = _ipfsFolder;
        extension = _extension;
    }
}

