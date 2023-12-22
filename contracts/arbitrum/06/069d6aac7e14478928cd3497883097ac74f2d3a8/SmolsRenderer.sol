// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
/*

SmolsRenderer.sol

Written by: mousedev.eth

*/


import "./ISchool.sol";
import "./ISmolsState.sol";
import "./ISmolsTraitStorage.sol";
import "./SmolsAddressRegistryConsumer.sol";

import "./AccessControlEnumerableV2.sol";
import "./SmolsLibrary.sol";

contract SmolsRenderer is AccessControlEnumerableV2, SmolsAddressRegistryConsumer  {
    uint256 public constant iqPerHeadSize = 50 * (10 ** 18);
    string public collectionDescription = "Smol Brains";
    string public namePrefix = "Smol #";


    /// @dev Gets a smol.
    /// @param _tokenId The smol to get.
    /// @return smol
    function getSmol(uint256 _tokenId) public view returns (Smol memory) {
        address smolsStateAddress = smolsAddressRegistry.getAddress(SmolAddressEnum.SMOLSSTATEADDRESS);
        address schoolAddress = smolsAddressRegistry.getAddress(SmolAddressEnum.SCHOOLADDRESS);
        address smolsAddress = smolsAddressRegistry.getAddress(SmolAddressEnum.SMOLSADDRESS);

        Smol memory _smolState = ISmolsState(smolsStateAddress).getSmol(
            _tokenId
        );

        uint128 totalStatPlusPendingEmissions = ISchool(schoolAddress).getTotalStatPlusPendingEmissions(smolsAddress, 0, _tokenId);

        if(totalStatPlusPendingEmissions < iqPerHeadSize * _smolState.headSize){
            //Too smol brain
            uint256 realHeadSize = totalStatPlusPendingEmissions / iqPerHeadSize;
            //If it's bigger than the max setting, set it to 5 as a sanity check. (theoretically shouldn't be possible, as you cannot set your head size higher.)
            if(realHeadSize > 5) {
                _smolState.headSize = 5;
            } else {
                _smolState.headSize = uint8(realHeadSize);
            }

        }

        return _smolState;
    }

    /// @dev Sets certain collection metadata.
    /// @param _collectionDescription A description of the collection.
    /// @param _namePrefix A prefix to use with the name of the tokens.
    function setCollectionData(
        string memory _collectionDescription,
        string memory _namePrefix
    ) external requiresEitherRole(OWNER_ROLE, SMOLS_RENDERER_ADMIN_ROLE) {
        if (bytes(_collectionDescription).length > 0)
            collectionDescription = _collectionDescription;
        if (bytes(_namePrefix).length > 0) namePrefix = _namePrefix;
    }


    function generatePNGFromTraitId(uint256 _traitId, uint8 _gender, uint256 _dependencyLevel)
        public
        view
        returns (bytes memory)
    {
        
        address smolsTraitStorageAddress = smolsAddressRegistry.getAddress(SmolAddressEnum.SMOLSTRAITSTORAGEADDRESS);

        return
            ISmolsTraitStorage(smolsTraitStorageAddress).getTraitImage(
                _traitId,
                _gender,
                _dependencyLevel
            );
    }

    function generateSVG(Smol memory _smol) public view returns (bytes memory) {
        if (_smol.skin > 0) {
            return
                abi.encodePacked(
                    '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" id="smol" width="100%" height="100%" version="1.1" viewBox="0 0 360 360" ',
                    'style="background-color: transparent;background-image:url(',
                    generatePNGFromTraitId(_smol.skin, _smol.gender, 0),
                    "),url(",
                    generatePNGFromTraitId(_smol.body, _smol.gender, 0),
                    "),url(",
                    generatePNGFromTraitId(_smol.background, _smol.gender, 0),
                    ')"',
                    ">",
                    "<style>#smol {background-repeat: no-repeat;background-size: contain;background-position: center;image-rendering: -webkit-optimize-contrast;-ms-interpolation-mode: nearest-neighbor;image-rendering: -moz-crisp-edges;image-rendering: pixelated;}</style></svg>"
                );
        }
        return
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" id="smol" width="100%" height="100%" version="1.1" viewBox="0 0 360 360" ',
                'style="background-color: transparent;background-image:url(',
                generatePNGFromTraitId(_smol.mouth, _smol.gender, 0),
                "),url(",
                generatePNGFromTraitId(_smol.hat, _smol.gender, _smol.headSize),
                "),url(",
                generatePNGFromTraitId(_smol.glasses, _smol.gender, 0),
                "),url(",
                generatePNGFromTraitId(_smol.clothes, _smol.gender, 0),
                "),url(",
                generatePNGFromTraitId(_smol.hair, _smol.gender, _smol.headSize),
                "),url(",
                generatePNGFromTraitId(_smol.body, _smol.gender, _smol.headSize),
                "),url(",
                generatePNGFromTraitId(_smol.background, _smol.gender, 0),
                ')"',
                ">",
                "<style>#smol {background-repeat: no-repeat;background-size: contain;background-position: center;image-rendering: -webkit-optimize-contrast;-ms-interpolation-mode: nearest-neighbor;image-rendering: -moz-crisp-edges;image-rendering: pixelated;}</style></svg>"
            );
    }

    function generateMetadataString(
        bytes memory traitType,
        bytes memory traitName
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                '{"trait_type":"',
                traitType,
                '","value":"',
                traitName,
                '"}'
            );
    }

    function generateMetadataStringForTrait(uint256 _traitId, uint8 _headSize)
        internal
        view
        returns (bytes memory)
    {
        return
            generateMetadataString(
                ISmolsTraitStorage(smolsAddressRegistry.getAddress(SmolAddressEnum.SMOLSTRAITSTORAGEADDRESS)).getTraitType(
                    _traitId,
                    _headSize
                ),
                ISmolsTraitStorage(smolsAddressRegistry.getAddress(SmolAddressEnum.SMOLSTRAITSTORAGEADDRESS)).getTraitName(
                    _traitId,
                    _headSize
                )
            );
    }

    function generateMetadataStringForNumber(
        bytes memory traitType,
        bytes memory traitValue
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                '{"trait_type":"',
                traitType,
                '","value":',
                traitValue,
                ',"display_type":"numeric"}'
            );
    }

    function generateMetadataStringForIQAndHeadsize(Smol memory _smol, uint256 _tokenId) public view returns(bytes memory){
        uint256 pendingIQ = ISchool(smolsAddressRegistry.getAddress(SmolAddressEnum.SCHOOLADDRESS)).getPendingStatEmissions(smolsAddressRegistry.getAddress(SmolAddressEnum.SMOLSADDRESS), 0, _tokenId) / 10 ** 18;
        uint256 IQ = ISchool(smolsAddressRegistry.getAddress(SmolAddressEnum.SCHOOLADDRESS)).tokenDetails(smolsAddressRegistry.getAddress(SmolAddressEnum.SMOLSADDRESS), 0, _tokenId).statAccrued / 10 ** 18;
    
        return abi.encodePacked(
            //Load the IQ
            generateMetadataStringForNumber(abi.encodePacked("IQ"), abi.encodePacked(SmolsLibrary.toString(IQ))),
            ",",
            //Load the pending IQ
            generateMetadataStringForNumber(abi.encodePacked("IQ Pending"), abi.encodePacked(SmolsLibrary.toString(pendingIQ))),
            ",",
            //Load the headsize
            generateMetadataStringForNumber(abi.encodePacked("Head Size"), abi.encodePacked(SmolsLibrary.toString(_smol.headSize)))
        );
    }

    function generateMetadata(Smol memory _smol, uint256 _tokenId)
        public
        view
        returns (bytes memory)
    {//If skin

        bytes memory genderBytes;

        if(_smol.gender == 1) genderBytes = bytes("male");
        if(_smol.gender == 2) genderBytes = bytes("female");

        if (_smol.skin > 0) {
        return abi.encodePacked(
                "[",
                //Load the IQ and headsize
                generateMetadataStringForIQAndHeadsize(_smol, _tokenId),
                ",",
                //Load the Skin
                generateMetadataStringForTrait(_smol.skin, 0),
                ",",
                //Load the Body
                generateMetadataStringForTrait(_smol.body, 0),
                ",",
                //Load the Background
                generateMetadataStringForTrait(_smol.background, 0),
                ",",
                //Load the Gender
                generateMetadataString(
                    "Gender",
                    genderBytes
                ),
                "]"
            );
        }

        //If not skin
        return
            abi.encodePacked(
                "[",
                //Load the IQ and headsize
                generateMetadataStringForIQAndHeadsize(_smol, _tokenId),
                ",",
                //Load the background
                generateMetadataStringForTrait(_smol.background, 0),
                ",",
                //Load the Body
                generateMetadataStringForTrait(_smol.body, _smol.headSize),
                ",",
                //Load the Clothes
                generateMetadataStringForTrait(_smol.clothes, 0),
                ",",
                //Load the Glasses
                generateMetadataStringForTrait(_smol.glasses, 0),
                ",",
                //Load the Hat
                generateMetadataStringForTrait(_smol.hat, _smol.headSize),
                ",",
                //Load the Hair
                generateMetadataStringForTrait(_smol.hair, _smol.headSize),
                ",",
                //Load the Mouth
                generateMetadataStringForTrait(_smol.mouth, 0),
                ",",
                //Load the Gender
                generateMetadataString(
                    "Gender",
                    genderBytes
                ),
                "]"
            );
    }


    /// @dev Consructs and returns an on chain smol.
    /// @param _tokenId The tokenId of the smol to return.
    /// @return smol The smol to return.
    function tokenURI(uint256 _tokenId) external view returns (string memory) {
        Smol memory _smol = getSmol(_tokenId);

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    SmolsLibrary.encode(
                        abi.encodePacked(
                            '{"description": "',
                            collectionDescription,
                            '","image": "data:image/svg+xml;base64,',
                            SmolsLibrary.encode(generateSVG(_smol)),
                            '","name": "',
                            namePrefix,
                            SmolsLibrary.toString(_tokenId),
                            '","attributes":',
                            generateMetadata(_smol, _tokenId),
                            "}"
                        )
                    )
                )
            );
    }
}

