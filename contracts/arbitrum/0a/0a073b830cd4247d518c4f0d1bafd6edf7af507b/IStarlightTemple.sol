// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStarlightTemple {

    // Increases a specific number of constellations to the max rank
    //
    function maxRankOfConstellations(uint256 _tokenId, uint8 _numberOfConstellations) external;
}
