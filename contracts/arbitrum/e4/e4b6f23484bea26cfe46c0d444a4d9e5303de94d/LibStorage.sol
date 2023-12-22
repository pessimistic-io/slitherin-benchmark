// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

/**
 * @title Storage for Bankroll
 */

struct GameStorage {
    mapping(address => bool) isGame;
    mapping(address => bool) isTokenAllowed;
    address[] allowedTokens; //Can be used to iterate through all tokens in bankroll to determine it's value
    address wrappedToken;
    mapping(address => uint256) suspendedTime;
    mapping(address => bool) isPlayerSuspended;
}

struct RewardStorage {
    mapping(address => mapping(address => uint256)) referralRewards;
    address manager;
    mapping(address => mapping(address => uint256)) l2eRewards;
}

library LibStorage {
    bytes32 constant GAME_STORAGE_POSITION = keccak256("zapankiswap.storage.game");
    bytes32 constant REWARD_STORAGE_POSITION = keccak256("zapankiswap.storage.reward");

    function gameStorage() internal pure returns (GameStorage storage gs) {
        bytes32 position = GAME_STORAGE_POSITION;
        assembly {
            gs.slot := position
        }
    }

    function rewardStorage() internal pure returns (RewardStorage storage rs) {
        bytes32 position = REWARD_STORAGE_POSITION;
        assembly {
            rs.slot := position
        }
    }
}

contract WithStorage {
    function gs() internal pure returns (GameStorage storage) {
        return LibStorage.gameStorage();
    }

    function rs() internal pure returns (RewardStorage storage) {
        return LibStorage.rewardStorage();
    }
}

