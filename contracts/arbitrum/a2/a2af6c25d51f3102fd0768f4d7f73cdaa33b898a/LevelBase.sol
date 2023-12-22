// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

import "./IPeekABoo.sol";
import "./IStakeManager.sol";

contract LevelBase {
    IPeekABoo public peekaboo;
    IStakeManager public stakeManager;

    uint256 BASE_EXP;
    uint256 EXP_GROWTH_RATE1;
    uint256 EXP_GROWTH_RATE2;

    mapping(uint256 => uint256) public tokenIdToEXP;
    mapping(uint256 => uint256) public difficultyToEXP;
    mapping(uint256 => mapping(uint256 => uint256)) public unlockedTraits;

    event LevelUp(uint256 tokenId);
}

