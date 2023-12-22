// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

library Types {
    struct FeePerGame {
        uint256 fee;
        bool isDone;
        bool isPresent;
    }

    struct Game {
        uint256 id;
        bool paused;
        string name;
        uint256 date;
        address impl;
    }

    struct GameWithExtraData {
        Game game;
        address vault;
        address token;
        uint256 minWager;
        uint256 maxPayout;
        uint256 maxReservedAmount;
        GameVaultReturn gameVault;
    }

    struct GameVault {
        GameFee gameFee;
        mapping(address => ReservedAmount) reservedAmount;
        bool isPresent;
    }

    struct GameVaultReturn {
        GameFee gameFee;
        bool isPresent;
    }

    struct GameFee {
        uint256 currentFee;
        uint256 nextFee;
        uint256 startTime;
    }

    struct ReservedAmount {
        uint256 amount;
        uint256 reserved;
        uint256 minWager;
    }
}

