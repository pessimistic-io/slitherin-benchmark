//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC1155Upgradeable.sol";

import "./AdminableUpgradeable.sol";
import "./BBase64.sol";

abstract contract ERC1155HybridUpgradeable is Initializable, ERC1155Upgradeable, AdminableUpgradeable {

    event TokenTraitChanged(uint256 _tokenId, TraitData _traitData);

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
        string url;
        Property[] properties;
    }

    // storage of each image data
    mapping(uint256 => TraitData) public tokenIdToTraitData;

    mapping(uint256 => mapping(string => string)) public tokenIdToPropertyNameToPropertyValue;

    function __ERC1155Hybrid_init() internal onlyInitializing {
        ERC1155Upgradeable.__ERC1155_init("");
        AdminableUpgradeable.__Adminable_init();
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        require(!paused(), "ERC1155Hybrid: Cannot transfer while paused");
    }

    function uploadTraitData(
        uint256 _tokenId,
        TraitData calldata _traitData)
    external
    onlyAdminOrOwner
    {

        Property[] memory _oldProperties = tokenIdToTraitData[_tokenId].properties;
        for(uint256 i = 0; i < _oldProperties.length; i++) {
            tokenIdToPropertyNameToPropertyValue[_tokenId][_oldProperties[i].name] = "";
        }

        tokenIdToTraitData[_tokenId] = _traitData;

        for(uint256 i = 0; i < _traitData.properties.length; i++) {
            tokenIdToPropertyNameToPropertyValue[_tokenId][_traitData.properties[i].name] = _traitData.properties[i].value;
        }

        emit TokenTraitChanged(_tokenId, _traitData);
    }

    function exists(uint256 _tokenId) public view returns(bool) {
        return !compareStrings(tokenIdToTraitData[_tokenId].name, "");
    }

    function propertyValueForToken(uint256 _tokenId, string calldata _propertyName) public view returns(string memory) {
        return tokenIdToPropertyNameToPropertyValue[_tokenId][_propertyName];
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
            '", "image": "',
            _traitData.url,
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

    modifier tokenIdExists(uint256 _tokenId) {
        require(exists(_tokenId), "ERC1155Hyrbid: Token ID does not exist");

        _;
    }

    uint256[48] private __gap;
}
