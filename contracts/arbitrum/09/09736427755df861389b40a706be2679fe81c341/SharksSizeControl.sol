// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import "./Sharks.sol";

contract SharksSizeControl {
    Sharks public sharks;

    constructor(address sharksAddress_) {
        sharks = Sharks(sharksAddress_);
    }

    function sharkSize(uint tokenId_) public view returns (uint256) {
        return sharks.xp(tokenId_) * sharks.rarity(tokenId_);
    }
}
