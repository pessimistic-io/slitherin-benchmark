// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IContractToBurn {
    function burn(uint256 tokenId) external;

    function balanceOf(address owner) external returns (uint256);

    function ownerOf(uint256 tokenId) external returns (address);
}

