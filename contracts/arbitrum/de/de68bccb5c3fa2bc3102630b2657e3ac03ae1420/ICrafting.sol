// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICrafting {

    function processCPGainAndLevelUp(uint256 _tokenId, uint8 _currentCraftingLevel, uint256 _craftingCPGained) external;
}
