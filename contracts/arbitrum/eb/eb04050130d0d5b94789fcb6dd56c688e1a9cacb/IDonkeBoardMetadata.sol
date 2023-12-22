//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

interface IDonkeBoardMetadata {
    function tokenURI(uint256 _tokenId) external view returns (string memory);

    function setBaseURI(string calldata _baseURI) external;
}

