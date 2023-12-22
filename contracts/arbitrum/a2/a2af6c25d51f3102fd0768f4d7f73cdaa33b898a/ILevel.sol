// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

import "./IPeekABoo.sol";
import "./IStakeManager.sol";

interface ILevel {
    function updateExp(
        uint256 tokenId,
        bool won,
        uint256 difficulty
    ) external;

    function expAmount(uint256 tokenId) external view returns (uint256);

    function isUnlocked(
        uint256 tokenId,
        uint256 traitType,
        uint256 traitId
    ) external returns (bool);

    function getUnlockedTraits(uint256 tokenId, uint256 traitType)
        external
        returns (uint256);
}

