// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

import {IUniswapV2Factory} from "./IUniswapV2Factory.sol";

interface IYapeFactory is IUniswapV2Factory {
    function registry() external view returns (address);

    function operator() external view returns (address);
}

