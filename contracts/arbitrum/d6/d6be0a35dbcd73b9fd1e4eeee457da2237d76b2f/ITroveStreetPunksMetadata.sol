// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface ITroveStreetPunksMetadata {

    function metadataOf(uint256 tokenId) external view returns (string memory);

}
