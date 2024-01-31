// SPDX-License-Identifier: MIT

/*********************************
*                                *
*           o(0 0)o              *
*             (^)                *
*                                *
 *********************************/

pragma solidity ^0.8.17;

interface IEchoMonkeysDescriptor {
    function tokenURI(uint256 tokenId, uint256 seed) external view returns (string memory);
}

