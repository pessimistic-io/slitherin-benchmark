// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IERC721Enumerable.sol";
import "./ISmolFarm.sol";

contract SmolBrainVerify {
    ISmolFarm private farm;
    IERC721Enumerable private smol;

    constructor() {
        farm = ISmolFarm(0xC2E007C61319fcf028178FAB14CD6ED6660C6e86);
        smol = IERC721Enumerable(0x6325439389E0797Ab35752B4F43a14C004f22A9c);
    }

    function balanceOf(address owner) external view returns (uint256) {
        uint256 balance = smol.balanceOf(owner);

        if (balance > 0) {
            return balance;
        }

        uint256 supply = smol.totalSupply();

        // If no balance, loop through farmers to see if one matches the owner being requested.
        for (uint256 index = 0; index < supply; index++) {
            if (ownerOf(index) == owner) {
                return 1;
            }
        }

        return 0;
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = smol.ownerOf(tokenId);

        if (owner != address(farm)) {
            return owner;
        }

        bool isOwner = farm.ownsToken(address(smol), msg.sender, tokenId);

        return isOwner ? msg.sender : address(0);
    }
}

