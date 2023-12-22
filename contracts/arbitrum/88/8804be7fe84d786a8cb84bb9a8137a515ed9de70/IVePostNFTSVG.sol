// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IVePostNFTSVG {
    function buildVePost(
        uint256 tokenId,
        uint8 typeVePost, // 0: Token, 1: LP NFT
        uint256 startTimeLock,
        uint256 endTimeLock,
        uint256 currentTime,
        uint256 boost,
        uint256 currentWeight
    ) external view returns (string memory);
}

