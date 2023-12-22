// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

interface IRenderer {
    function tokenURI(uint256 tokenId, address escrow) external view returns (string memory svgString);
}

