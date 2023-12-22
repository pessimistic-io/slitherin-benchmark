// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {Hop} from "./LibHop.sol";

interface IRouter1 {
    function swapBalancerV2(Hop calldata h) external payable;

    function swapCurve(Hop calldata h) external payable;

    function swapDodoV2(Hop calldata h) external payable;

    function swapGmx(Hop calldata h) external payable;

    function swapHashflow(Hop calldata h) external payable;

    function swapIntegralSize(Hop calldata h) external payable;

    function swapKyberClassic(Hop calldata h) external payable;

    function swapKyberElastic(Hop memory h) external payable;

    function swapTrident(Hop calldata h) external payable;

    function swapUniswapV2(Hop calldata h) external payable;

    function swapUniswapV3(Hop calldata h) external payable;

    function swapWoofi(Hop calldata h) external payable;

    function swapAlgebra(Hop calldata h) external payable;

    function swapSaddle(Hop calldata h) external payable;
}

