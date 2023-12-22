// SPDX-License-Identifier: None
pragma solidity >=0.5.0;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";

interface IAlcorOptionPool {
    // function getRecipientCallback() external view returns (address);

    function mint(int24 tickLower, int24 tickUpper, uint128 amount) external returns (uint256 amount0, uint256 amount1);

    function burn(int24 tickLower, int24 tickUpper, uint128 amount) external returns (uint256 amount0, uint256 amount1);

    function collectFees(int24 tickLower, int24 tickUpper) external returns (uint128 amount0, uint128 amount1);

    function swap(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) external returns (int256 amount0, int256 amount1);
}

