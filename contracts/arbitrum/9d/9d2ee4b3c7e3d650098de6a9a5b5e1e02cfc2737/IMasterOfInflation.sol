// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMasterOfInflation {

    function tryMintFromPool(
        MintFromPoolParams calldata _params)
    external
    returns(bool _didMintItem);
}

struct MintFromPoolParams {
    // Slot 1 (160/256)
    uint64 poolId;
    uint64 amount;
    // Extra odds (out of 100,000) of pulling the item. Will be multiplied against the base odds
    // (1 + bonus) * dynamicBaseOdds
    uint32 bonus;

    // Slot 2
    uint256 itemId;

    // Slot 3
    uint256 randomNumber;

    // Slot 4 (160/256)
    address user;
}
