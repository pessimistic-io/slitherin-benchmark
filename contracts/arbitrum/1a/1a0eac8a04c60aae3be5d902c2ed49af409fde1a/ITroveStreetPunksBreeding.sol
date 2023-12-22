// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface ITroveStreetPunksBreeding {

    function kids(uint256 _tokenId) external view returns (uint256);

    function maxKids(uint256 _tokenId) external view returns (uint256);

}
