// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface Smols {
    function ownerOf(uint256 tokenId) external view returns (address owner);

    function walletOfOwner(
        address _address
    ) external view returns (uint256[] memory);
}

