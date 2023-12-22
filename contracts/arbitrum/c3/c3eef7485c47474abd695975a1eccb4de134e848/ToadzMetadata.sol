//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./StringsUpgradeable.sol";

import "./BBase64.sol";
import "./ToadzMetadataContracts.sol";

contract ToadzMetadata is Initializable, ToadzMetadataContracts {

    using StringsUpgradeable for uint256;

    function initialize() external initializer {
        ToadzMetadataContracts.__ToadzMetadataContracts_init();
    }

    function setMetadataForToad(uint256 _tokenId, ToadTraits calldata _traits) external whenNotPaused onlyAdminOrOwner {
        tokenIdToTraits[_tokenId] = _traits;

        emit ToadzMetadataChanged(_tokenId, _toadTraitsToToadTraitStrings(_traits));
    }

    function _toadTraitsToToadTraitStrings(ToadTraits calldata _traits) private view returns(ToadTraitStrings memory) {
        return ToadTraitStrings(
            rarityToString[_traits.rarity],
            backgroundToString[_traits.background],
            mushroomToString[_traits.mushroom],
            skinToString[_traits.skin],
            clothesToString[_traits.clothes],
            mouthToString[_traits.mouth],
            eyesToString[_traits.eyes],
            itemToString[_traits.item],
            headToString[_traits.head],
            accessoryToString[_traits.accessory]
        );
    }

    function tokenURI(uint256 _tokenId) public view override returns(string memory) {
        ToadTraits memory _traits = tokenIdToTraits[_tokenId];

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
            '{"name":"Toad #',
            _tokenId.toString(),
            '", "description":"Toadstoolz is an on-chain toad life simulation NFT game. Toadz love to hunt for $BUGZ, go on adventures and are obsessed with collecting NFTs.", "image": "',
            'data:image/svg+xml;base64,');
    }

    function _getAttributes(ToadTraits memory _traits) private view returns(string memory) {
        return string(abi.encodePacked(
            '"attributes": [',
                _getTopAttributes(_traits),
                _getBottomAttributes(_traits),
            ']'
        ));
    }

    function _getTopAttributes(ToadTraits memory _traits) private view returns(string memory) {
        return string(abi.encodePacked(
            _getRarityJSON(_traits.rarity), ',',
            _getBackgroundJSON(_traits.background), ',',
            _getMushroomJSON(_traits.mushroom), ',',
            _getSkinJSON(_traits.skin), ',',
            _getClothesJSON(_traits.clothes), ','
        ));
    }

    function _getBottomAttributes(ToadTraits memory _traits) private view returns(string memory) {
        return string(abi.encodePacked(
            _getMouthJSON(_traits.mouth), ',',
            _getEyesJSON(_traits.eyes), ',',
            _getItemJSON(_traits.item), ',',
            _getHeadJSON(_traits.head), ',',
            _getAccessoryJSON(_traits.accessory)
        ));
    }

    function _getRarityJSON(ToadRarity _rarity) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            ToadTraitConstants.RARITY,
            '","value":"',
            rarityToString[_rarity],
            '"}'
        ));
    }

    function _getBackgroundJSON(ToadBackground _background) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            ToadTraitConstants.BACKGROUND,
            '","value":"',
            backgroundToString[_background],
            '"}'
        ));
    }

    function _getMushroomJSON(ToadMushroom _mushroom) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            ToadTraitConstants.MUSHROOM,
            '","value":"',
            mushroomToString[_mushroom],
            '"}'
        ));
    }

    function _getSkinJSON(ToadSkin _skin) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            ToadTraitConstants.SKIN,
            '","value":"',
            skinToString[_skin],
            '"}'
        ));
    }

    function _getClothesJSON(ToadClothes _clothes) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            ToadTraitConstants.CLOTHES,
            '","value":"',
            clothesToString[_clothes],
            '"}'
        ));
    }

    function _getMouthJSON(ToadMouth _mouth) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            ToadTraitConstants.MOUTH,
            '","value":"',
            mouthToString[_mouth],
            '"}'
        ));
    }

    function _getEyesJSON(ToadEyes _eyes) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            ToadTraitConstants.EYES,
            '","value":"',
            eyesToString[_eyes],
            '"}'
        ));
    }

    function _getItemJSON(ToadItem _item) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            ToadTraitConstants.ITEM,
            '","value":"',
            itemToString[_item],
            '"}'
        ));
    }

    function _getHeadJSON(ToadHead _head) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            ToadTraitConstants.HEAD,
            '","value":"',
            headToString[_head],
            '"}'
        ));
    }

    function _getAccessoryJSON(ToadAccessory _accessory) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            ToadTraitConstants.ACCESSORY,
            '","value":"',
            accessoryToString[_accessory],
            '"}'
        ));
    }

    function getSVG(ToadTraits memory _traits) public view returns(string memory) {
        return BBase64.encode(bytes(string(abi.encodePacked(
            '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg" xmlns:xhtml="http://www.w3.org/1999/xhtml" style="shape-rendering:crispedges;image-rendering:pixelated;-ms-interpolation-mode:nearest-neighbor">',
            _getTopSVGParts(_traits),
            _getBottomSVGParts(_traits),
            '</svg>'
        ))));
    }

    function _getTopSVGParts(ToadTraits memory _traits) private view returns(string memory) {
        return string(abi.encodePacked(
            _getBackgroundSVGPart(_traits.background),
            _getMushroomSVGPart(_traits.mushroom),
            _getSkinSVGPart(_traits.skin),
            _getClothesSVGPart(_traits.clothes),
            _getAccessorySVGPart(_traits.accessory)
        ));
    }

    function _getBottomSVGParts(ToadTraits memory _traits) private view returns(string memory) {
        return string(abi.encodePacked(
            _getMouthSVGPart(_traits.mouth),
            _getEyesSVGPart(_traits.eyes),
            _getHeadSVGPart(_traits.head),
            _getItemSVGPart(_traits.item)
        ));
    }

    function _getBackgroundSVGPart(ToadBackground _background) private view returns(string memory) {
        return wrapPNG(backgroundToPNG[_background]);
    }

    function _getMushroomSVGPart(ToadMushroom _mushroom) private view returns(string memory) {
        return wrapPNG(mushroomToPNG[_mushroom]);
    }

    function _getSkinSVGPart(ToadSkin _skin) private view returns(string memory) {
        return wrapPNG(skinToPNG[_skin]);
    }

    function _getClothesSVGPart(ToadClothes _clothes) private view returns(string memory) {
        if(_clothes == ToadClothes.NONE) {
            return "";
        }
        return wrapPNG(clothesToPNG[_clothes]);
    }

    function _getMouthSVGPart(ToadMouth _mouth) private view returns(string memory) {
        if(_mouth == ToadMouth.NONE) {
            return "";
        }
        return wrapPNG(mouthToPNG[_mouth]);
    }

    function _getEyesSVGPart(ToadEyes _eyes) private view returns(string memory) {
        if(_eyes == ToadEyes.NONE) {
            return "";
        }
        return wrapPNG(eyesToPNG[_eyes]);
    }

    function _getItemSVGPart(ToadItem _item) private view returns(string memory) {
        if(_item == ToadItem.NONE) {
            return "";
        }
        return wrapPNG(itemToPNG[_item]);
    }

    function _getHeadSVGPart(ToadHead _head) private view returns(string memory) {
        if(_head == ToadHead.NONE) {
            return "";
        }
        return wrapPNG(headToPNG[_head]);
    }

    function _getAccessorySVGPart(ToadAccessory _accessory) private view returns(string memory) {
        if(_accessory == ToadAccessory.NONE) {
            return "";
        }
        return wrapPNG(accessoryToPNG[_accessory]);
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
        require(_traits.length == _strings.length, "ToadzMetadata: Invalid array lengths");

        for(uint256 i = 0; i < _traits.length; i++) {
            if(compareStrings(_category, ToadTraitConstants.BACKGROUND)) {
                backgroundToString[ToadBackground(_traits[i])] = _strings[i];
            } else if(compareStrings(_category, ToadTraitConstants.MUSHROOM)) {
                mushroomToString[ToadMushroom(_traits[i])] = _strings[i];
            } else if(compareStrings(_category, ToadTraitConstants.SKIN)) {
                skinToString[ToadSkin(_traits[i])] = _strings[i];
            } else if(compareStrings(_category, ToadTraitConstants.CLOTHES)) {
                clothesToString[ToadClothes(_traits[i])] = _strings[i];
            } else if(compareStrings(_category, ToadTraitConstants.MOUTH)) {
                mouthToString[ToadMouth(_traits[i])] = _strings[i];
            } else if(compareStrings(_category, ToadTraitConstants.EYES)) {
                eyesToString[ToadEyes(_traits[i])] = _strings[i];
            } else if(compareStrings(_category, ToadTraitConstants.ITEM)) {
                itemToString[ToadItem(_traits[i])] = _strings[i];
            } else if(compareStrings(_category, ToadTraitConstants.HEAD)) {
                headToString[ToadHead(_traits[i])] = _strings[i];
            } else if(compareStrings(_category, ToadTraitConstants.ACCESSORY)) {
                accessoryToString[ToadAccessory(_traits[i])] = _strings[i];
            } else {
                revert("ToadzMetadata: Invalid category");
            }
        }
    }

    function setPNGData(
        string calldata _category,
        uint8[] calldata _traits,
        string[] calldata _pngDatas)
    external
    onlyAdminOrOwner
    {
        require(_traits.length == _pngDatas.length, "ToadzMetadata: Invalid array lengths");

        for(uint256 i = 0; i < _traits.length; i++) {
            if(compareStrings(_category, ToadTraitConstants.BACKGROUND)) {
                backgroundToPNG[ToadBackground(_traits[i])] = _pngDatas[i];
            } else if(compareStrings(_category, ToadTraitConstants.MUSHROOM)) {
                mushroomToPNG[ToadMushroom(_traits[i])] = _pngDatas[i];
            } else if(compareStrings(_category, ToadTraitConstants.SKIN)) {
                skinToPNG[ToadSkin(_traits[i])] = _pngDatas[i];
            } else if(compareStrings(_category, ToadTraitConstants.CLOTHES)) {
                clothesToPNG[ToadClothes(_traits[i])] = _pngDatas[i];
            } else if(compareStrings(_category, ToadTraitConstants.MOUTH)) {
                mouthToPNG[ToadMouth(_traits[i])] = _pngDatas[i];
            } else if(compareStrings(_category, ToadTraitConstants.EYES)) {
                eyesToPNG[ToadEyes(_traits[i])] = _pngDatas[i];
            } else if(compareStrings(_category, ToadTraitConstants.ITEM)) {
                itemToPNG[ToadItem(_traits[i])] = _pngDatas[i];
            } else if(compareStrings(_category, ToadTraitConstants.HEAD)) {
                headToPNG[ToadHead(_traits[i])] = _pngDatas[i];
            } else if(compareStrings(_category, ToadTraitConstants.ACCESSORY)) {
                accessoryToPNG[ToadAccessory(_traits[i])] = _pngDatas[i];
            } else {
                revert("ToadzMetadata: Invalid category");
            }
        }
    }

}
