//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ToadzMinterContracts.sol";

abstract contract ToadzMinterSettings is Initializable, ToadzMinterContracts {

    function __ToadzMinterSettings_init() internal initializer {
        ToadzMinterContracts.__ToadzMinterContracts_init();
    }

    function setRaritiesForTrait(
        string calldata _traitType,
        uint8[] calldata _rarities,
        uint8[] calldata _aliases)
    external
    onlyAdminOrOwner
    {
        require(_rarities.length > 0, "ToadzMinter: 0 length for rarities");
        require(_rarities.length == _aliases.length, "ToadzMinter: Rarity and alias lengths do not match");

        delete traitTypeToRarities[_traitType];
        delete traitTypeToAliases[_traitType];

        // Must preserve order/index of rarities and aliases.
        for(uint256 i = 0; i < _rarities.length; i++) {
            traitTypeToRarities[_traitType].push(_rarities[i]);
            traitTypeToAliases[_traitType].push(_aliases[i]);
        }
    }
}
