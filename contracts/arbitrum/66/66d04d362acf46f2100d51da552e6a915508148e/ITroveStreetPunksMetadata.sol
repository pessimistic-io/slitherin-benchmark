// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface ITroveStreetPunksMetadata {

    function supplyDna(uint256 _tokenId, uint256 _dna, bytes memory _signature) external;

    function metadataOf(uint256 _tokenId) external view returns (string memory);

    function traitsOf(uint256 _tokenId) external view returns (uint256[] memory);

    function dnaOf(uint256 _tokenId) external view returns (uint256);

    function exists(uint256 _tokenId) external view returns (bool);

}
