// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;
    enum ActionType {
        ADD_LIQUIDITY, // D2, D6 < 0
        REMOVE_LIQUIDITY, // D2, D6 > 0

        SUPPLY_BASE_TOKEN, // D4 > 0
        WITHDRAW_BASE_TOKEN, // D4 < 0

        BORROW_SIDE_TOKEN, // D5 > 0
        REPAY_SIDE_TOKEN, // D5 < 0

        SWAP_SIDE_TO_BASE, // D3 < 0
        SWAP_BASE_TO_SIDE  // D3 > 0
    }


        enum Method {
            NOTHING,
            STAKE,
            UNSTAKE
        }

    // Amounts in decimals specific token, all positive
        struct Amounts {
            uint256 baseCollateral;
            uint256 sideBorrow;
            uint256 basePool;
            uint256 sidePool;
            uint256 baseFree;
            uint256 sideFree;
        }

    // liquidity in USD e6, all positive
        struct Liquidity {
            int256 baseCollateral;
            int256 sideBorrow;
            int256 basePool;
            int256 sidePool;
            int256 baseFree;
            int256 sideFree;
        }

        struct CalcContext {
            int256 K1; // in e18
            int256 K2; // in e18
            int256 K3; // in e18
            int256 amount; // amount in USD, below zero if UNSTAKE
            Liquidity liq; // in USD e6
            uint256 tokenAssetSlippagePercent;
            Deltas deltas; // in USD e6
        }

        struct Action2 {
            uint256 actionType;
            uint256 amount;
            uint256 slippagePercent;
        }


        struct Action {
            ActionType actionType;
            uint256 amount;
            uint256 slippagePercent;
        }


        struct CalcContextRequest {
            int256 K1; // in e18
            int256 K2; // in e18
            int256 K3; // in e18
            int256 amount; // amount in USD, below zero if UNSTAKE
            Liquidity liq; // in USD e6
            uint256 tokenAssetSlippagePercent;
        }

    // liquidity deltas in USD e6, may contain zeroes and below zero
        struct Deltas {
            // int256 d1;
            int256 d2;
            int256 d3;
            int256 d4;
            int256 d5;
            int256 d6;
            uint256 code;
        }

