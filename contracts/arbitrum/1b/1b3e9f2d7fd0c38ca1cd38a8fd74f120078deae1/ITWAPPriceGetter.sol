// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IUniswapV3Pool.sol";

interface ITWAPPriceGetter {
    function token() external view returns (address);

    function uniV3Pool() external view returns (IUniswapV3Pool);

    function twapInterval() external view returns (uint32);

    function isGnsToken0InLp() external view returns (bool);

    function tokenPriceUsdc() external view returns (uint price);
}

