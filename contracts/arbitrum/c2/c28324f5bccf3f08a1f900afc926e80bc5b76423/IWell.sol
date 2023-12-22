// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

interface IWell {
    struct sWell {
        uint8 level;
        uint32 speedBuf;
        uint32 tokenId;
    }
    function mint(address _to) external;
    function updateTokenTraits(sWell memory _w) external;
    function getTokenTraits(uint256 _tokenId) external view returns (sWell memory);
}
