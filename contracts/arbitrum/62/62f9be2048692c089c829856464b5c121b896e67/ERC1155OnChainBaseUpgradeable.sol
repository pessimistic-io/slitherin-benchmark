//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC1155Upgradeable.sol";

import "./AdminableUpgradeable.sol";
import "./BBase64.sol";

abstract contract ERC1155OnChainBaseUpgradeable is Initializable, AdminableUpgradeable, ERC1155Upgradeable {

    event TokenTraitChanged(uint256 _tokenId, string _name, string _description, Property[] _properties);

    enum PropertyType {
        STRING,
        NUMBER
    }

    struct Property {
        string name;
        string value;
        PropertyType propertyType;
    }

    struct TraitData {
        string name;
        string description;
        string png;
        Property[] properties;
    }

    // storage of each image data
    mapping(uint256 => TraitData) public tokenIdToTraitData;

    function __ERC1155OnChainBase_init() internal initializer {
        // Empty because it's generated on-chain
        ERC1155Upgradeable.__ERC1155_init("");
        AdminableUpgradeable.__Adminable_init();
    }

    function uploadTraitData(
        uint256 _tokenId,
        TraitData calldata _traitData)
    external
    onlyAdminOrOwner
    {
        tokenIdToTraitData[_tokenId] = _traitData;

        emit TokenTraitChanged(_tokenId, _traitData.name, _traitData.description, _traitData.properties);
    }

    function exists(uint256 _tokenId) public view returns(bool) {
        return !compareStrings(tokenIdToTraitData[_tokenId].name, "");
    }

    function uri(
        uint256 _tokenId)
    public
    view
    override
    tokenIdExists(_tokenId)
    returns(string memory)
    {
        TraitData storage _traitData = tokenIdToTraitData[_tokenId];
        string memory metadata = string(abi.encodePacked(
            '{"name": "',
            _traitData.name,
            '", "description": "',
            _traitData.description,
            '", "image": "data:image/svg+xml;base64,',
            BBase64.encode(bytes(_drawSVG(_tokenId))),
            '", "attributes": [',
            _generateAttributeString(_traitData),
            ']}'
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            BBase64.encode(bytes(metadata))
        ));
    }

    function _generateAttributeString(TraitData storage _traitData) private view returns(string memory) {
        if(_traitData.properties.length == 0) {
            return '';
        }

        string memory _returnString;

        for(uint256 i = 0; i < _traitData.properties.length; i++) {

            _returnString = string(abi.encodePacked(
                _returnString,
                '{"trait_type":"',
                _traitData.properties[i].name,
                '","value":',
                _traitData.properties[i].propertyType == PropertyType.STRING ? '"' : '',
                _traitData.properties[i].value,
                _traitData.properties[i].propertyType == PropertyType.STRING ? '"' : '',
                '}',
                i < _traitData.properties.length - 1 ? ',' : ''
            ));
        }

        return _returnString;
    }

    function _drawImage(TraitData memory image) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<image x="0" y="0" width="64" height="64" image-rendering="pixelated" preserveAspectRatio="xMidYMid" xlink:href="data:image/png;base64,',
            image.png,
            '"/>'
        ));
    }

    function _drawSVG(uint256 _tokenId) internal view returns (string memory) {
        string memory svgString = string(abi.encodePacked(
            _drawImage(tokenIdToTraitData[_tokenId])
        ));

        return string(abi.encodePacked(
            '<svg id="imageRender" width="100%" height="100%" version="1.1" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">',
            svgString,
            "</svg>"
        ));
    }

    modifier tokenIdExists(uint256 _tokenId) {
        require(exists(_tokenId), "ERC1155OnChainBase: Token ID does not exist");

        _;
    }

    uint256[50] private __gap;
}
