//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./SoLItemContracts.sol";
import "./BBase64.sol";

contract SoLItem is Initializable, SoLItemContracts {

    function initialize() external initializer {
        SoLItemContracts.__SoLItemContracts_init();
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

    function mint(
        address _to,
        uint256 _id,
        uint256 _amount)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    {
        _mint(_to, _id, _amount, "");
    }
}
