// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.14;

/// @dev Separate storage contract to improve upgrade safety
abstract contract FolfSeason23NFTStorageV1 {
    string public baseURI;

    struct FolfGameData {
        address[2] players;
        uint16[2] score;
        bool[2] accepted;
        address winner;
    }
    mapping(uint256 => FolfGameData) internal tokenIdToFolfGameData;

    function getFolfGameDataFromTokenId(uint256 _tokenId) external view returns(FolfGameData memory d) {
        return tokenIdToFolfGameData[_tokenId];
    }
}

abstract contract FolfSeason23NFTStorage is FolfSeason23NFTStorageV1 {}

