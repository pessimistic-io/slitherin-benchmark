//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./StringsUpgradeable.sol";

import "./BBase64.sol";
import "./ToadHousezMetadataContracts.sol";

contract ToadHousezMetadata is Initializable, ToadHousezMetadataContracts {

    using StringsUpgradeable for uint256;

    function initialize() external initializer {
        ToadHousezMetadataContracts.__ToadHousezMetadataContracts_init();
    }

    function setMetadataForHouse(uint256 _tokenId, ToadHouseTraits calldata _traits) external whenNotPaused onlyAdminOrOwner {
        tokenIdToTraits[_tokenId] = _traits;

        emit ToadHousezMetadataChanged(_tokenId, _toadTraitsToToadTraitStrings(_traits));
    }

    function _toadTraitsToToadTraitStrings(ToadHouseTraits calldata _traits) private view returns(ToadHouseTraitStrings memory) {
        return ToadHouseTraitStrings(
            rarityToString[_traits.rarity],
            uint8(_traits.variation) + 1,
            backgroundToString[_traits.background],
            baseToString[_traits.base],
            woodTypeToString[_traits.main],
            woodTypeToString[_traits.left],
            woodTypeToString[_traits.right],
            woodTypeToString[_traits.door],
            woodTypeToString[_traits.mushroom]
        );
    }

    function tokenURI(uint256 _tokenId) public view override returns(string memory) {
        ToadHouseTraits memory _traits = tokenIdToTraits[_tokenId];

        bytes memory _beginningJSON = _getBeginningJSON(_tokenId);
        string memory _svg = getSVG(_traits);
        string memory _attributes = _getAttributes(_traits);

        return string(
            abi.encodePacked(
                'data:application/json;base64,',
                BBase64.encode(
                    bytes(
                        abi.encodePacked(
                            _beginningJSON,
                            _svg,
                            '",',
                            _attributes,
                            '}'
                        )
                    )
                )
            )
        );
    }

    function _getBeginningJSON(uint256 _tokenId) private pure returns(bytes memory) {
        return abi.encodePacked(
            '{"name":"Toad House #',
            _tokenId.toString(),
            '", "description":"Toadstoolz is an on-chain toad life simulation NFT game. Toadz love to hunt for $BUGZ, go on adventures and are obsessed with collecting NFTs.", "image": "',
            'data:image/svg+xml;base64,');
    }

    function _getAttributes(ToadHouseTraits memory _traits) private view returns(string memory) {
        return string(abi.encodePacked(
            '"attributes": [',
                _getTopAttributes(_traits),
                _getBottomAttributes(_traits),
            ']'
        ));
    }

    function _getTopAttributes(ToadHouseTraits memory _traits) private view returns(string memory) {
        return string(abi.encodePacked(
            _getRarityJSON(_traits.rarity), ',',
            _getHouseVariationJSON(_traits.variation, VARIATION), ',',
            _getBackgroundJSON(_traits.background), ',',
            _getBaseJSON(_traits.base), ',',
            _getWoodJSON(_traits.main, MAIN), ',',
            _getWoodJSON(_traits.left, LEFT), ',',
            _getWoodJSON(_traits.right, RIGHT), ','
        ));
    }

    function _getBottomAttributes(ToadHouseTraits memory _traits) private view returns(string memory) {
        return string(abi.encodePacked(
            _getWoodJSON(_traits.door, DOOR), ',',
            _getWoodJSON(_traits.mushroom, MUSHROOM), ','
        ));
    }

    function _getRarityJSON(HouseRarity _rarity) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            RARITY,
            '","value":"',
            rarityToString[_rarity],
            '"}'
        ));
    }

    function _getBackgroundJSON(HouseBackground _background) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            BACKGROUND,
            '","value":"',
            backgroundToString[_background],
            '"}'
        ));
    }

    function _getBaseJSON(HouseBase _base) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            BASE,
            '","value":"',
            baseToString[_base],
            '"}'
        ));
    }

    function _getWoodJSON(WoodType _woodType, string memory _traitName) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            _traitName,
            '","value":"',
            woodTypeToString[_woodType],
            '"}'
        ));
    }

    function _getHouseVariationJSON(HouseVariation _houseVariation, string memory _traitName) private pure returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            _traitName,
            '","value":',
            // 1 based value
            (uint256(_houseVariation) + 1).toString(),
            '}'
        ));
    }

    function getSVG(ToadHouseTraits memory _traits) public view returns(string memory) {
        return BBase64.encode(bytes(string(abi.encodePacked(
            '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg" xmlns:xhtml="http://www.w3.org/1999/xhtml" style="shape-rendering:crispedges;image-rendering:pixelated;-ms-interpolation-mode:nearest-neighbor">',
            _getTopSVGParts(_traits),
            _getBottomSVGParts(_traits),
            '</svg>'
        ))));
    }

    function _getTopSVGParts(ToadHouseTraits memory _traits) private view returns(string memory) {
        return string(abi.encodePacked(
            _getBackgroundSVGPart(_traits.background)
        ));
    }

    function _getBottomSVGParts(ToadHouseTraits memory _traits) private view returns(string memory) {
        return string(abi.encodePacked(
            _getBaseSVGPart(_traits.base)
        ));
    }

    function _getBackgroundSVGPart(HouseBackground _background) private view returns(string memory) {
        return wrapPNG(backgroundToPNG[_background]);
    }

    function _getBaseSVGPart(HouseBase _base) private view returns(string memory) {
        return wrapPNG(baseToPNG[_base]);
    }

    function wrapPNG(string memory _png) internal pure returns(string memory) {
        return string(abi.encodePacked(
            '<foreignObject x="0" y="0" height="64" width="64"><xhtml:img src="data:image/png;base64,',
            _png,
            '"/></foreignObject>'
        ));
    }

    function setTraitStrings(
        string calldata _category,
        uint8[] calldata _traits,
        string[] calldata _strings)
    external
    onlyAdminOrOwner
    {
        require(_traits.length == _strings.length, "ToadHousezMetadata: Invalid array lengths");

        for(uint256 i = 0; i < _traits.length; i++) {
            if(compareStrings(_category, BACKGROUND)) {
                backgroundToString[HouseBackground(_traits[i])] = _strings[i];
            } else if(compareStrings(_category, BASE)) {
                baseToString[HouseBase(_traits[i])] = _strings[i];
            } else if(compareStrings(_category, WOOD_TYPE)) {
                woodTypeToString[WoodType(_traits[i])] = _strings[i];
            } else {
                revert("ToadHousezMetadata: Invalid category");
            }
        }
    }

    function setPNGData(
        string calldata _category,
        uint8[] calldata _variations,
        uint8[] calldata _traits,
        string[] calldata _pngDatas)
    external
    onlyAdminOrOwner
    {
        require(_traits.length == _pngDatas.length
            && _variations.length == _traits.length, "ToadHousezMetadata: Invalid array lengths");

        for(uint256 i = 0; i < _traits.length; i++) {
            if(compareStrings(_category, BACKGROUND)) {
                backgroundToPNG[HouseBackground(_traits[i])] = _pngDatas[i];
            } else if(compareStrings(_category, BASE)) {
                baseToPNG[HouseBase(_traits[i])] = _pngDatas[i];
            } else if(compareStrings(_category, MAIN)) {
                WoodType _woodType = WoodType(_traits[i]);
                HouseVariation _houseVariation = HouseVariation(_variations[i]);

                mainToVariationToPNG[_woodType][_houseVariation] = _pngDatas[i];
            } else if(compareStrings(_category, LEFT)) {
                WoodType _woodType = WoodType(_traits[i]);
                HouseVariation _houseVariation = HouseVariation(_variations[i]);

                leftToVariationToPNG[_woodType][_houseVariation] = _pngDatas[i];
            } else if(compareStrings(_category, RIGHT)) {
                WoodType _woodType = WoodType(_traits[i]);
                HouseVariation _houseVariation = HouseVariation(_variations[i]);

                rightToVariationToPNG[_woodType][_houseVariation] = _pngDatas[i];
            } else if(compareStrings(_category, DOOR)) {
                WoodType _woodType = WoodType(_traits[i]);
                HouseVariation _houseVariation = HouseVariation(_variations[i]);

                doorToVariationToPNG[_woodType][_houseVariation] = _pngDatas[i];
            } else if(compareStrings(_category, MUSHROOM)) {
                WoodType _woodType = WoodType(_traits[i]);
                HouseVariation _houseVariation = HouseVariation(_variations[i]);

                mushroomToVariationToPNG[_woodType][_houseVariation] = _pngDatas[i];
            } else {
                revert("ToadHousezMetadata: Invalid category");
            }
        }
    }

}
