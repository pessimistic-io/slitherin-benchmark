// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IGenesisOwnership {
    function ownerOf(uint256 tokenId) external view returns (address);
}
