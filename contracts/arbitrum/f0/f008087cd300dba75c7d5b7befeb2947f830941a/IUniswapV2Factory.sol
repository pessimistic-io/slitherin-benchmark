// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./IERC20.sol";
import "./IUniswapV2Pair.sol";

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

