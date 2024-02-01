// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721Burnable.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./base64.sol";
import "./IPingMetadataTraits.sol";
import "./IPingMetadata.sol";
import "./IPingRenderer.sol";
import "./PingAtts.sol";

contract PingMetadata is IPingMetadata, ReentrancyGuard, Ownable {
    using Strings for uint;

    address public _traitsAddr;
    address public _previewerAddr;
    address public _rendererAddr;

    string _externalUri = "https://twitter.com/BlockGenerative";
    string description = "Generative coded art as part of BlockGenerative collection.";
    string name = "Pings";

    function setTraitsAddr(address addr) external virtual onlyOwner {
        _traitsAddr = addr;
    }

    function setPreviewerAddr(address addr) external virtual onlyOwner {
        _previewerAddr = addr;
    }

    function setRendererAddr(address addr) external virtual onlyOwner {
        _rendererAddr = addr;
    }

    function genMetadata(uint256 tokenId, PingAtts calldata atts) external view virtual override returns (string memory) {
        require(address(_previewerAddr) != address(0), "No preview address");
        require(address(_traitsAddr) != address(0), "No traits address");

        IPingRenderer previewer = IPingRenderer(_previewerAddr);
        string memory previewImage = previewer.render(tokenId, atts, true);

        string memory render;
        if(address(_rendererAddr) != address(0)) {
            IPingRenderer renderer = IPingRenderer(_rendererAddr);
            render = renderer.render(tokenId, atts, false);
        }
        else {
            render = previewImage;
        }

        string memory attrOutput;

        if (address(_traitsAddr) != address(0)) {
            IPingMetadataTraits traits = IPingMetadataTraits(_traitsAddr);
            attrOutput = traits.getTraits(atts);
        } else {
            attrOutput = "";
        }

        string memory json = Base64.encode(abi.encodePacked(
                abi.encodePacked(
                    '{"name":"', getTokenName(tokenId),
                    '","description":"', getDescription(tokenId),
                    '","attributes":', attrOutput,
                    ',"image":"', previewImage,
                    '","animation_url":"', render
                ),
                abi.encodePacked(
                    '","external_url":"', getExternalUrl(), '"}'
                )));

        return string(abi.encodePacked('data:application/json;base64,', json));
    }

    function getTokenName(uint256 tokenId) public view virtual returns (string memory) {
        return string.concat(name, " #", tokenId.toString());
    }

    function setName(string memory text) external virtual onlyOwner {
        name = text;
    }

    function getDescription(uint256) public view virtual returns (string memory) {
        return description;
    }

    function setDescription(string memory text) external virtual onlyOwner {
        description = text;
    }

    function getExternalUrl() public view virtual returns (string memory) {
        return _externalUri;
    }

    function setExternalUrl(string memory uri) external virtual onlyOwner {
        _externalUri = uri;
    }

    function validateContract() external view returns (string memory){
        if(address(_previewerAddr) == address(0)) { return "No preview address"; }
        if(address(_traitsAddr) == address(0)) { return "No traits address"; }

        IPingRenderer previewer = IPingRenderer(_previewerAddr);
        IPingMetadataTraits traits = IPingMetadataTraits(_traitsAddr);

        string memory result = previewer.validateContract();
        if(bytes(result).length > 0) {
            return result;
        }
        else {
            return traits.validateContract();
        }
    }

}
