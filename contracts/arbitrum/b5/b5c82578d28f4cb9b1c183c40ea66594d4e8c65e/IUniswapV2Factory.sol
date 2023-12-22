// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IERC4626} from "./ERC4626.sol";

interface IUniswapV2Factory {
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address);
}

