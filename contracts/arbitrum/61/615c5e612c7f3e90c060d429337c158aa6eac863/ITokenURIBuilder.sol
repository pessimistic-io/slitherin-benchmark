// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0 <0.9.0;

interface ITokenURIBuilder {
    function buildTokenURI(uint256 seed, uint256 tokenId) external view returns (string memory);
}

