// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20} from "./IERC20.sol";

import "./errors.sol";
import "./DefiOp.sol";

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

abstract contract BaseLendingArbitrum is DefiOp {
    IERC20 constant USDT = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    IERC20 constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20 constant DAI = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    IERC20 constant WBTC = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IWETH constant WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 constant wstETH = IERC20(0x5979D7b546E38E414F7E9822514be443A4800529);

    modifier checkToken(IERC20 token) {
        if (token != USDT && token != USDC && token != DAI)
            revert UnsupportedToken();
        _;
    }
}

