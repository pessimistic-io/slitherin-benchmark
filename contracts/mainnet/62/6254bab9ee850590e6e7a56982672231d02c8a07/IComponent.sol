// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IComponent {
    function adminClaim(uint256 tokenId, address receiver) external;
}

