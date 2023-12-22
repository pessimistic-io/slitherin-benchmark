// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface ISmolsState {

    struct PngImage {
        bytes male;
        bytes female;
    }
    
    struct Trait {
        uint8 gender;
        uint24 traitId;
        bytes traitName;
        bytes traitType;
        PngImage pngImage;
    }

    struct Smol {
        uint24 background;
        uint24 body;
        uint24 clothes;
        uint24 mouth;
        uint24 glasses;
        uint24 hat;
        uint24 hair;
        uint24 skin;
        uint8 gender;
        //0 - Unset
        //1 - Male
        //2 - Female
        uint8 headSize;
    }

    function getSmol(uint256 tokenId) external view returns (Smol memory);

    function getInitialSmol(uint256 tokenId) external view returns (Smol memory);

    function setSmol(uint256 tokenId, Smol memory) external;

    function setInitialSmol(uint256 tokenId, Smol memory) external;

    function setBackground(uint256 _tokenId, uint24 _traitId) external;

    function setBody(uint256 _tokenId, uint24 _traitId) external;

    function setClothes(uint256 _tokenId, uint24 _traitId) external;

    function setMouth(uint256 _tokenId, uint24 _traitId) external;

    function setGlasses(uint256 _tokenId, uint24 _traitId) external;

    function setHat(uint256 _tokenId, uint24 _traitId) external;

    function setHair(uint256 _tokenId, uint24 _traitId) external;

    function setSkin(uint256 _tokenId, uint24 _traitId) external;

    function setGender(uint256 _tokenId, uint8 _gender) external;

    function setHeadSize(uint256 _tokenId, uint8 _headSize) external;
}
