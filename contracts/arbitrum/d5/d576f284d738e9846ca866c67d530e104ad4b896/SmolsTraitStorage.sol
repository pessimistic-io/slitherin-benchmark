// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/*

SmolsTraitStorage.sol

Written by: mousedev.eth

*/

import "./UtilitiesV2Upgradeable.sol";
import "./SmolsLibrary.sol";

contract SmolsTraitStorage is UtilitiesV2Upgradeable {
    mapping(uint256 => mapping(uint256 => Trait)) public traits;

    event TraitAdded(uint256 _traitId, uint256 _dependencyLevel, Trait _trait);

    /// @dev Set a single trait and dependency level to a trait.
    /// @param _traitId The trait id to set.
    /// @param _dependencyLevel The dependency level to set.
    /// @param _trait The trait to set.
    /// @param _override Whether to override an already set trait
    function setTrait(
        uint256 _traitId,
        uint256 _dependencyLevel,
        Trait calldata _trait,
        bool _override
    ) external requiresEitherRole(OWNER_ROLE, SMOLS_TRAIT_STORAGE_ADMIN_ROLE) {
        require(_trait.traitId > 0, "Cannot have 0 as trait id");
        if(_override) {
            traits[_traitId][_dependencyLevel] = _trait;
        } else {
            require(traits[_traitId][_dependencyLevel].traitId == 0, "Trait already set!");
            traits[_traitId][_dependencyLevel] = _trait;
        }

        emit TraitAdded(_traitId, _dependencyLevel, _trait);
    }

    /// @dev Sets multiple traitIds and dependency levels to traits.
    /// @param _traitIds The trait ids to set.
    /// @param _dependencyLevels The dependency levels to set.
    /// @param _traits The traits to set.
    /// @param _override Whether to override an already set trait
    function setTraits(
        uint256[] calldata _traitIds,
        uint256[] calldata _dependencyLevels,
        Trait[] calldata _traits,
        bool _override
    ) external requiresEitherRole(OWNER_ROLE, SMOLS_TRAIT_STORAGE_ADMIN_ROLE) {
        for (uint256 i = 0; i < _traits.length; i++) {
            require(_traits[i].traitId > 0, "Cannot have 0 as trait id");
            if(_override) {
                traits[_traitIds[i]][_dependencyLevels[i]] = _traits[i];
            } else {
                require(traits[_traitIds[i]][_dependencyLevels[i]].traitId == 0, "Trait already set!");
                traits[_traitIds[i]][_dependencyLevels[i]] = _traits[i];
            }
            
            emit TraitAdded(_traitIds[i], _dependencyLevels[i], _traits[i]);
        }
    }

    /// @dev Returns a single Trait struct from a traitId and dependencyLevel.
    /// @param _traitId The trait id to return.
    /// @param _dependencyLevel The dependency level of that trait to return.
    /// @return Trait The trait to return.
    function getTrait(uint256 _traitId, uint256 _dependencyLevel)
        external
        view
        returns (Trait memory)
    {
        return traits[_traitId][_dependencyLevel];
    }

    /// @dev Returns a single trait type from a traitId and dependencyLevel.
    /// @param _traitId The trait id to return.
    /// @param _dependencyLevel The dependency level of that trait to return.
    /// @return traitType The trait type to return.
    function getTraitType(uint256 _traitId, uint256 _dependencyLevel)
        external
        view
        returns (bytes memory)
    {
        return traits[_traitId][_dependencyLevel].traitType;
    }

    /// @dev Returns a single trait name from a traitId and dependencyLevel.
    /// @param _traitId The trait id to return.
    /// @param _dependencyLevel The dependency level of that trait to return.
    /// @return traitName The trait name to return.
    function getTraitName(uint256 _traitId, uint256 _dependencyLevel)
        external
        view
        returns (bytes memory)
    {
        return traits[_traitId][_dependencyLevel].traitName;
    }


    /// @dev Returns whether a trait is detachable
    /// @param _traitId The trait id to return.
    /// @param _dependencyLevel The dependency level of that trait to return.
    /// @return isDetachable Whether it is detachable.
    function getIsDetachable(uint256 _traitId, uint256 _dependencyLevel)
        external
        view
        returns (bool)
    {
        return traits[_traitId][_dependencyLevel].isDetachable;
    }


    /// @dev Returns a single trait image from a traitId and dependencyLevel.
    /// @param _traitId The trait id to return.
    /// @param _dependencyLevel The dependency level of that trait to return.
    /// @param _gender The gender of the trait to return.
    /// @return traitImage The trait image to return.
    function getTraitImage(uint256 _traitId, uint8 _gender, uint256 _dependencyLevel)
        external
        view
        returns (bytes memory)
    {
        if(_gender == 1){
            return traits[_traitId][_dependencyLevel].pngImage.male;
        }
        if(_gender == 2){
            return traits[_traitId][_dependencyLevel].pngImage.female;
        }

        revert("Gender not specified");
    }


    // -------------------------------------------------------------
    //                       Initializer
    // -------------------------------------------------------------

    function initialize() public initializer {
        UtilitiesV2Upgradeable.__Utilities_init();
    }

    
    uint256[50] private __gap;
}

