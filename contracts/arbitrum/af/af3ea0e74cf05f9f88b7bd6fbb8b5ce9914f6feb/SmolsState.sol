// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/*

SmolsState.sol

Written by: mousedev.eth

*/

import "./UtilitiesV2Upgradeable.sol";
import "./SmolsLibrary.sol";

contract SmolsState is UtilitiesV2Upgradeable {

    event HeadSizeUpdated(uint256 _smolId, uint256 _headSize);
    event GenderUpdated(uint256 _smolId, uint256 _gender);

    event SkinUpdated(uint256 _smolId, uint256 _traitId);
    event HairUpdated(uint256 _smolId, uint256 _traitId);
    event HatUpdated(uint256 _smolId, uint256 _traitId);
    event GlassesUpdated(uint256 _smolId, uint256 _traitId);
    event MouthUpdated(uint256 _smolId, uint256 _traitId);
    event ClothesUpdated(uint256 _smolId, uint256 _traitId);
    event BodyUpdated(uint256 _smolId, uint256 _traitId);
    event BackgroundUpdated(uint256 _smolId, uint256 _traitId);


    event FullSmolUpdated(uint256 _smolId, Smol _smol);
    event InitialSmolSet(uint256 _smolId, Smol _smol);

    mapping(uint256 => Smol) public smolToTraits;
    mapping(uint256 => Smol) public initialSmolToTraits;

    /// @dev Returns a smol struct representing the current adjusted state of the smol.
    /// @param _tokenId The smol to get.
    /// @return Smol The smol you requested.
    function getSmol(uint256 _tokenId) external view returns (Smol memory) {
        return smolToTraits[_tokenId];
    }

    /// @dev Returns a smol struct representing the initial state of the smol.
    /// @param _tokenId The smol to get.
    /// @return Smol The smol you requested.
    function getInitialSmol(uint256 _tokenId) external view returns (Smol memory) {
        return initialSmolToTraits[_tokenId];
    }

    /// @dev Adjust smol data.
    /// @param _tokenId The smol to get.
    /// @param _smol The smol data to set.
    function setSmol(uint256 _tokenId, Smol memory _smol)
        external
        requiresRole(SMOLS_STATE_SETTER_ROLE)
    {
        smolToTraits[_tokenId] = _smol;

        emit FullSmolUpdated(_tokenId, _smol);
    }

    /// @dev Adjust smol initial data.
    /// @param _tokenId The smol to get.
    /// @param _smol The smol data to set.
    function setInitialSmol(uint256 _tokenId, Smol memory _smol)
        external
        requiresRole(SMOLS_STATE_EXCHANGER_ROLE)
    {
        initialSmolToTraits[_tokenId] = _smol;
        smolToTraits[_tokenId] = _smol;

        emit InitialSmolSet(_tokenId, _smol);
    }

    /// @dev Adjust smol trait.
    /// @param _tokenId The smol to set.
    /// @param _traitId The smol traitId to set this trait to.
    function setBackground(uint256 _tokenId, uint24 _traitId)
        external
        requiresRole(SMOLS_STATE_SETTER_ROLE)
        returns(bool _overwritten, uint256 _previousTraitId)
    {
        //If the currently equipped trait matches the initial trait, do not detach.
        //If the currently equipped trait does not match the initial trait, detach.
        if(smolToTraits[_tokenId].background != initialSmolToTraits[_tokenId].background) _overwritten = true; 

        //Set the previous traitId for return
        _previousTraitId = smolToTraits[_tokenId].background;

        //If they are wanting to detach
        if(_traitId == 0){
            //Set the background trait to the initial smol data
            smolToTraits[_tokenId].background = initialSmolToTraits[_tokenId].background;
            emit BackgroundUpdated(_tokenId, initialSmolToTraits[_tokenId].background);
        } else {
            //Set the background trait to the desired traitId
            smolToTraits[_tokenId].background = _traitId;
            emit BackgroundUpdated(_tokenId, _traitId);
        }
    }

    /// @dev Adjust smol trait.
    /// @param _tokenId The smol to set.
    /// @param _traitId The smol traitId to set this trait to.
    function setBody(uint256 _tokenId, uint24 _traitId)
        external
        requiresRole(SMOLS_STATE_SETTER_ROLE)
        returns(bool _overwritten, uint256 _previousTraitId)
    {
        //If the currently equipped trait matches the initial trait, do not detach.
        //If the currently equipped trait does not match the initial trait, detach.
        if(smolToTraits[_tokenId].body != initialSmolToTraits[_tokenId].body) _overwritten = true; 

        //Set the previous traitId for return
        _previousTraitId = smolToTraits[_tokenId].body;

        //If they are wanting to detach
        if(_traitId == 0){
            //Set the body trait to the initial smol data
            smolToTraits[_tokenId].body = initialSmolToTraits[_tokenId].body;
            emit BodyUpdated(_tokenId, initialSmolToTraits[_tokenId].body);
        } else {
            //Set the body trait to the desired traitId
            smolToTraits[_tokenId].body = _traitId;
            emit BodyUpdated(_tokenId, _traitId);
        }
    }

    /// @dev Adjust smol trait.
    /// @param _tokenId The smol to set.
    /// @param _traitId The smol traitId to set this trait to.
    function setClothes(uint256 _tokenId, uint24 _traitId)
        external
        requiresRole(SMOLS_STATE_SETTER_ROLE)
        returns(bool _overwritten, uint256 _previousTraitId)
    {
        //If the currently equipped trait matches the initial trait, do not detach.
        //If the currently equipped trait does not match the initial trait, detach.
        if(smolToTraits[_tokenId].clothes != initialSmolToTraits[_tokenId].clothes) _overwritten = true; 

        //Set the previous traitId for return
        _previousTraitId = smolToTraits[_tokenId].clothes;

        //If they are wanting to detach
        if(_traitId == 0){
            //Set the clothes trait to the initial smol data
            smolToTraits[_tokenId].clothes = initialSmolToTraits[_tokenId].clothes;
            emit ClothesUpdated(_tokenId, initialSmolToTraits[_tokenId].clothes);
        } else {
            //Set the clothes trait to the desired traitId
            smolToTraits[_tokenId].clothes = _traitId;
            emit ClothesUpdated(_tokenId, _traitId);
        }
    }

    /// @dev Adjust smol trait.
    /// @param _tokenId The smol to set.
    /// @param _traitId The smol traitId to set this trait to.
    function setMouth(uint256 _tokenId, uint24 _traitId)
        external
        requiresRole(SMOLS_STATE_SETTER_ROLE)
        returns(bool _overwritten, uint256 _previousTraitId)
    {
        //If the currently equipped trait matches the initial trait, do not detach.
        //If the currently equipped trait does not match the initial trait, detach.
        if(smolToTraits[_tokenId].mouth != initialSmolToTraits[_tokenId].mouth) _overwritten = true; 

        //Set the previous traitId for return
        _previousTraitId = smolToTraits[_tokenId].mouth;

        //If they are wanting to detach
        if(_traitId == 0){
            //Set the mouth trait to the initial smol data
            smolToTraits[_tokenId].mouth = initialSmolToTraits[_tokenId].mouth;
            emit MouthUpdated(_tokenId, initialSmolToTraits[_tokenId].mouth);
        } else {
            //Set the mouth trait to the desired traitId
            smolToTraits[_tokenId].mouth = _traitId;
            emit MouthUpdated(_tokenId, _traitId);
        }
    }

    /// @dev Adjust smol trait.
    /// @param _tokenId The smol to set.
    /// @param _traitId The smol traitId to set this trait to.
    function setGlasses(uint256 _tokenId, uint24 _traitId)
        external
        requiresRole(SMOLS_STATE_SETTER_ROLE)
        returns(bool _overwritten, uint256 _previousTraitId)
    {
        //If the currently equipped trait matches the initial trait, do not detach.
        //If the currently equipped trait does not match the initial trait, detach.
        if(smolToTraits[_tokenId].glasses != initialSmolToTraits[_tokenId].glasses) _overwritten = true; 

        //Set the previous traitId for return
        _previousTraitId = smolToTraits[_tokenId].glasses;

        //If they are wanting to detach
        if(_traitId == 0){
            //Set the glasses trait to the initial smol data
            smolToTraits[_tokenId].glasses = initialSmolToTraits[_tokenId].glasses;
            emit GlassesUpdated(_tokenId, initialSmolToTraits[_tokenId].glasses);
        } else {
            //Set the glasses trait to the desired traitId
            smolToTraits[_tokenId].glasses = _traitId;
            emit GlassesUpdated(_tokenId, _traitId);
        }
    }

    /// @dev Adjust smol trait.
    /// @param _tokenId The smol to set.
    /// @param _traitId The smol traitId to set this trait to.
    function setHat(uint256 _tokenId, uint24 _traitId)
        external
        requiresRole(SMOLS_STATE_SETTER_ROLE)
        returns(bool _overwritten, uint256 _previousTraitId)
    {
        //If the currently equipped trait matches the initial trait, do not detach.
        //If the currently equipped trait does not match the initial trait, detach.
        if(smolToTraits[_tokenId].hat != initialSmolToTraits[_tokenId].hat) _overwritten = true; 

        //Set the previous traitId for return
        _previousTraitId = smolToTraits[_tokenId].hat;
        
        //If they are wanting to detach
        if(_traitId == 0){
            //Set the hat trait to the initial smol data
            smolToTraits[_tokenId].hat = initialSmolToTraits[_tokenId].hat;
            emit HatUpdated(_tokenId, initialSmolToTraits[_tokenId].hat);
        } else {
            //Set the hat trait to the desired traitId
            smolToTraits[_tokenId].hat = _traitId;
            emit HatUpdated(_tokenId, _traitId);
        }
    }

    /// @dev Adjust smol trait.
    /// @param _tokenId The smol to set.
    /// @param _traitId The smol traitId to set this trait to.
    function setHair(uint256 _tokenId, uint24 _traitId)
        external
        requiresRole(SMOLS_STATE_SETTER_ROLE)
        returns(bool _overwritten, uint256 _previousTraitId)
    {
        //If the currently equipped trait matches the initial trait, do not detach.
        //If the currently equipped trait does not match the initial trait, detach.
        if(smolToTraits[_tokenId].hair != initialSmolToTraits[_tokenId].hair) _overwritten = true; 

        //Set the previous traitId for return
        _previousTraitId = smolToTraits[_tokenId].hair;

        //If they are wanting to detach
        if(_traitId == 0){
            //Set the hair trait to the initial smol data
            smolToTraits[_tokenId].hair = initialSmolToTraits[_tokenId].hair;
            emit HairUpdated(_tokenId, initialSmolToTraits[_tokenId].hair);
        } else {
            //Set the hair trait to the desired traitId
            smolToTraits[_tokenId].hair = _traitId;
            emit HairUpdated(_tokenId, _traitId);
        }
    }

    /// @dev Adjust smol trait.
    /// @param _tokenId The smol to set.
    /// @param _traitId The smol traitId to set this trait to.
    function setSkin(uint256 _tokenId, uint24 _traitId)
        external
        requiresRole(SMOLS_STATE_SETTER_ROLE)
        returns(bool _overwritten, uint256 _previousTraitId)
    {
        //If they already had a skin, they would be overwriting it.
        if(smolToTraits[_tokenId].skin > 0) _overwritten = true; 

        //Set the previous traitId for return
        _previousTraitId = smolToTraits[_tokenId].skin;

        smolToTraits[_tokenId].skin = _traitId;
        emit SkinUpdated(_tokenId, _traitId);
    }

    /// @dev Adjust smol gender.
    /// @param _tokenId The smol to set.
    /// @param _gender The smol gender to set this smol to.
    function setGender(uint256 _tokenId, uint8 _gender)
        external
        requiresRole(SMOLS_STATE_SETTER_ROLE)
    {
        smolToTraits[_tokenId].gender = _gender;
        emit GenderUpdated(_tokenId, _gender);
    }

    /// @dev Adjust smol headsize.
    /// @param _tokenId The smol to set.
    /// @param _headSize The smol headsize to set it to.
    function setHeadSize(uint256 _tokenId, uint8 _headSize)
        external
        requiresRole(SMOLS_STATE_SETTER_ROLE)
    {
        smolToTraits[_tokenId].headSize = _headSize;
        emit HeadSizeUpdated(_tokenId, _headSize);
    }

    // -------------------------------------------------------------
    //                       Initializer
    // -------------------------------------------------------------

    function initialize() public initializer {
        UtilitiesV2Upgradeable.__Utilities_init();
    }

    uint256[50] private __gap;
}

