// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct BankrollStorage {
    mapping(address => bool) isGame;
    mapping(address => bool) isTokenAllowed;
    address[] allowedTokens;
    address __deleted_1;
    mapping(address => uint256) __deleted_2;
    mapping(address => bool) __deleted_3;
}

struct L2EStorage {
    uint256 l2eRatio;
    address l2eToken;
}

library LibStorage {
    bytes32 constant BANKROLL_STORAGE_POSITION = keccak256("zapankiswap.storage.game");
    bytes32 constant L2E_STORAGE_POSITION = keccak256("zapankiswap.storage.2.l2e");

    function bankrollStorage() internal pure returns (BankrollStorage storage bs) {
        bytes32 position = BANKROLL_STORAGE_POSITION;
        assembly {
            bs.slot := position
        }
    }

    function l2eStorage() internal pure returns (L2EStorage storage ls) {
        bytes32 position = L2E_STORAGE_POSITION;
        assembly {
            ls.slot := position
        }
    }
}

contract WithStorage {
    function bs() internal pure returns (BankrollStorage storage) {
        return LibStorage.bankrollStorage();
    }

    function ls() internal pure returns (L2EStorage storage) {
        return LibStorage.l2eStorage();
    }
}

