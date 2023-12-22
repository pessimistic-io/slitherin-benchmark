// SPDX-License-Identifier: None
pragma solidity ^0.8.18;

import {VanillaOptionPool} from "./VanillaOptionPool.sol";

interface IVanillaOption {
    event OptionExpired(uint256 price);
    event AlcorMint(
        address indexed owner,
        uint256 amount0Delta,
        uint256 amount1Delta
    );
    event AlcorBurn(
        address indexed owner,
        uint256 amount0ToTransfer,
        uint256 amount1ToTransfer
    );
    event AlcorCollect(address indexed owner, uint128 amount0, uint128 amount1);
    event AlcorWithdraw(uint256 payoutAmount);
    event AlcorSwap(address indexed owner, int256 amount0, int256 amount1);
    event AlcorUpdatePosition(
        address indexed owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 newLiquidity
    );
    event AlcorAddOptionPool(
        uint256 indexed expiry,
        uint256 indexed strike,
        bool indexed isCall,
        address conjugatedUniPool
    );
    event AlcorInitOptionPool(
        uint256 indexed expiry,
        uint256 indexed strike,
        bool indexed isCall,
        int24 tick
    );

    function swap(
        // address owner,
        VanillaOptionPool.Key memory optionPoolKey,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) external returns (int256 amount0ToTransfer, int256 amount1ToTransfer);
}

