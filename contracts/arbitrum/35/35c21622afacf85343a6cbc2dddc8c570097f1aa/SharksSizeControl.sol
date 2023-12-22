// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import "./Sharks.sol";
import "./GangsMultiplierManagement.sol";

contract SharksSizeControl {
    Sharks public sharks;
    GangsMultiplierManagement public gangsMultiplierManagement;

    constructor(address sharksAddress_, address gangsMultiplierManagementAddress_) {
        sharks = Sharks(sharksAddress_);
        gangsMultiplierManagement = GangsMultiplierManagement(gangsMultiplierManagementAddress_);
    }

    function sharkSize(uint tokenId_) public view returns (uint256) {
        uint256 size = sharks.xp(tokenId_) * sharks.rarity(tokenId_);
        uint256 gangsMultiplier = gangsMultiplierManagement.getMultiplierBySharkId(tokenId_);

        if (gangsMultiplier > 0) {
            size = size * gangsMultiplier / 100;
        }

        return size;
    }
}
