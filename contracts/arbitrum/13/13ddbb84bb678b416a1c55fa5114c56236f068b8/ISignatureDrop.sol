// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface ISignatureDrop {
    function balanceOf(address owner) external view returns (uint256 balance);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function tokenURI(uint256 _tokenId) external view returns (string memory);

    function totalMinted() external view returns (uint256);
}

