// SPDX-License-Identifier: None
pragma solidity ^0.8.18;

import {FullMath} from "./FullMath.sol";

library VanillaOptionPool {
    struct Key {
        uint256 expiry;
        uint256 strike;
        bool isCall;
    }

    function hashOptionPool(
        Key memory optionPoolKey
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    optionPoolKey.expiry,
                    optionPoolKey.strike,
                    optionPoolKey.isCall
                )
            );
    }

    struct PoolBalance {
        uint256 token0Balance;
        uint256 token1Balance;
    }

    function updatePoolBalances(
        mapping(bytes32 vaillaOptionPoolHash => PoolBalance) storage self,
        bytes32 optionPoolKeyHash,
        int256 token0Delta,
        int256 token1Delta
    ) internal {
        PoolBalance storage poolBalances = self[optionPoolKeyHash];

        // token0
        if (token0Delta > 0) poolBalances.token0Balance += uint256(token0Delta);
        else poolBalances.token0Balance -= uint256(-token0Delta);
        // token1
        if (token1Delta > 0) poolBalances.token1Balance += uint256(token1Delta);
        else poolBalances.token1Balance -= uint256(-token1Delta);
    }

    // function updatePoolBalances(
    //     mapping(bytes32 => PoolBalance) storage self,
    //     Key memory optionPoolKey,
    //     int256 token0Delta,
    //     int256 token1Delta
    // ) internal {
    //     PoolBalance storage poolBalances = self[hashOptionPool(optionPoolKey)];

    //     // token0
    //     if (token0Delta > 0) poolBalances.token0Balance += uint256(token0Delta);
    //     else poolBalances.token0Balance -= uint256(-token0Delta);
    //     // token1
    //     if (token1Delta > 0) poolBalances.token1Balance += uint256(token1Delta);
    //     else poolBalances.token1Balance -= uint256(-token1Delta);
    // }

    // @dev both strike and priceAtExpiry must be expressed in terms of 1e18
    function calculateVanillaCallPayoffInAsset(
        bool isLong,
        uint256 strike,
        uint256 priceAtExpiry,
        uint8 token1Decimals
    ) internal pure returns (uint256 payoff) {
        if (priceAtExpiry > strike) {
            payoff = FullMath.mulDiv(
                (priceAtExpiry - strike),
                10 ** token1Decimals,
                priceAtExpiry
            );
        } else {
            payoff = 0;
        }
        if (isLong) {
            return payoff;
        } else {
            return 10 ** token1Decimals - payoff;
        }
    }

    // @dev both strike and priceAtExpiry must be expressed in terms of 1e18
    function calculatePayoffPutOption(
        bool isLong,
        uint256 strike,
        uint256 priceAtExpiry,
        uint8 token0Decimals
    ) internal pure returns (uint256 payoff) {
        if (priceAtExpiry < strike) {
            payoff = FullMath.mulDiv(
                (priceAtExpiry - strike),
                10 ** token0Decimals,
                1 ether
            );
        } else {
            payoff = 0;
        }
        if (isLong) {
            return payoff;
        } else {
            return 10 ** token0Decimals - payoff;
        }
    }
}

