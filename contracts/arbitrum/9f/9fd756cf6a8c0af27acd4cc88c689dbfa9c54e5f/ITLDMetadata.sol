// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITLDMetadata {
    // Returns the tokenUri for the given token. Initially, will be used to return IPFS metadata before
    // an eventual effort to migrate things on-chain is done
    function tokenURI(uint256 _tokenId) external view returns (string memory);

    // Modifies the baseUri. Admin only
    function setBaseURI(string calldata _baseURI) external;
}

