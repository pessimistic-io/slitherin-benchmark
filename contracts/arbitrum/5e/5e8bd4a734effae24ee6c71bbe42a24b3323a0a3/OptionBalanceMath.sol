// SPDX-License-Identifier: None
pragma solidity ^0.8.18;

import {VanillaOptionPool} from "./VanillaOptionPool.sol";

library OptionBalanceMath {
    // methods for user's option balances
    function getOptionBalance(
        mapping(address => mapping(bytes32 => int256)) storage self,
        address owner,
        bytes32 comboOptionPoolKeyHash
    ) internal view returns (int256 optionBalance) {
        optionBalance = self[owner][comboOptionPoolKeyHash];
    }

    // methods for user's option balances
    function updateOptionBalance(
        mapping(address => mapping(bytes32 => int256)) storage self,
        address owner,
        bytes32 comboOptionPoolKeyHash,
        int256 balanceDelta
    ) internal {
        self[owner][comboOptionPoolKeyHash] += balanceDelta;
    }

    // @dev amount to transfer is amount that user must transfer (if < 0 then pool must transfer)
    function calculateNewOptionBalance(
        int256 userOptionBalance,
        int256 amount0,
        int256 amount1
    ) internal pure returns (int256 amount0PoolShouldTransfer, int256 amount1PoolShouldTransfer) {
        if (amount1 < 0) {
            if (userOptionBalance < 0 && userOptionBalance - amount1 > 0) {
                // this is the case when user was in short options, but after this purchase had become in long options
                // pool should transfer only amount that equals to user's previous option balance
                amount1PoolShouldTransfer = -userOptionBalance;
            } else if (userOptionBalance < 0 && userOptionBalance - amount1 < 0) {
                // in this case user was in short options and still remains in short options
                // pool should transfer the delta amount
                amount1PoolShouldTransfer = -amount1;
            } else if (userOptionBalance >= 0) {
                // in this case user was in long options and (obviously) remains in long options
                // pool must not transfer any collateral
            }
            // user must pay in token0
            amount0PoolShouldTransfer = -amount0;
        }
        // user sells options
        else {
            if (userOptionBalance > 0 && userOptionBalance - amount1 < 0) {
                // in this case user was in long options, but became in short options
                // user should transfer additional collateral
                amount1PoolShouldTransfer = (userOptionBalance - amount1);
            } else if (userOptionBalance > 0 && userOptionBalance - amount1 > 0) {
                // in this case user was in long options and still remains in long options
                // no transfers of collateral
            } else if (userOptionBalance <= 0) {
                // in this case user was in short options and (obviously) remains in short options
                // user should transfer additional collateral
                amount1PoolShouldTransfer = -amount1;
            }
            // pool transfers the option premium to user
            amount0PoolShouldTransfer = -amount0;
        }
    }
}

