// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface ICrafting {
    function startCraftingForToad(StartCraftingParams calldata _startCraftingParams, address _owner) external returns(bool);

    function endCraftingForToad(uint256 _toadId, address _owner) external;
}

struct StartCraftingParams {
    uint64 toadId;
    uint64 recipeId;
    ItemInfo[] inputs;
}

struct ItemInfo {
    uint64 itemId;
    uint64 amount;
}
