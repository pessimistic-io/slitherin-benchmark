//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC1155Upgradeable.sol";

import "./ISoLItem.sol";
import "./AdminableUpgradeable.sol";

abstract contract SoLItemState is Initializable, ISoLItem, ERC1155Upgradeable, AdminableUpgradeable {

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

    function __SoLItemState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC1155Upgradeable.__ERC1155_init("");
    }
}
