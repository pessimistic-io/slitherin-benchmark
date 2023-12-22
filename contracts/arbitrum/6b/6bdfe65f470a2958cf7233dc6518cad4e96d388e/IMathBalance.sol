// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

enum ActionType {
    ADD_LIQUIDITY,
    REMOVE_LIQUIDITY,
    SUPPLY_BASE_TOKEN,
    WITHDRAW_BASE_TOKEN,
    BORROW_SIDE_TOKEN,
    REPAY_SIDE_TOKEN,
    SWAP_SIDE_TO_BASE,
    SWAP_BASE_TO_SIDE
}
struct Action {
    ActionType actionType;
    uint256 amount;
}

struct BalanceMathInput {
    int256 k1;
    int256 k2;
    int256 k3;
    int256 amount;
    int256 baseCollateral;
    int256 sideBorrow;
    int256 sidePool;
    int256 baseFree;
    int256 sideFree;
    int256 tokenAssetSlippagePercent;
}

interface IMathBalance {
function balance(BalanceMathInput calldata i
    )
        external
        view
        returns (
            Action[] memory actions
        );
}
