// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";
import {ILP} from "./ILP.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";

library LPMath {
    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // Given an amount of Liquidity, return tokens amounts.
    function breakFromLiquidityAmount(address _lp, uint256 _liquidityAmount) public view returns (uint256, uint256) {
        uint256 totalLiquidity = IERC20(_lp).totalSupply();

        IERC20 _tokenA = IERC20(IUniswapV2Pair(_lp).token0());
        IERC20 _tokenB = IERC20(IUniswapV2Pair(_lp).token1());

        uint256 _amountA = (_tokenA.balanceOf(_lp) * _liquidityAmount) / totalLiquidity;
        uint256 _amountB = (_tokenB.balanceOf(_lp) * _liquidityAmount) / totalLiquidity;

        return (_amountA, _amountB);
    }

    // Given an amount of ETH, simulate how much LP it represents
    function ethToLiquidity(address _lp, uint256 _ethAmount) public view returns (uint256) {
        uint256 totalSupply = IERC20(_lp).totalSupply();
        uint256 totalEth = IERC20(weth).balanceOf(_lp);

        return (totalSupply * _ethAmount) / totalEth * 2;
    }
}

