// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

interface IMine {
    struct sMine {
        uint8 cid;
        uint8 nftType;
        uint8 gen;
        uint32 tokenId;
        uint32 speedBuf;
        uint256 capacity;
        uint256 cumulativeOutput;
    }
    function updateTokenTraits(sMine memory _w) external;
    function getTokenTraits(uint256 _tokenId) external view returns (sMine memory);
    function getReferrer(address _account) external view returns(address[2] memory);
    function eachTypeG0Capacity() external view returns(uint256[3] memory capacity_);
}
