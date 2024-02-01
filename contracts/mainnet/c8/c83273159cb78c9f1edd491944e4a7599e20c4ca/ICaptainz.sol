// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./IERC721.sol";

interface ICaptainz {
    function tokensLastQuestedAt(uint256 tokenId) external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address);

    function getActiveCrews(uint256 tokenId) external view returns (uint256[] memory);
}

