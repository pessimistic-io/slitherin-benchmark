// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Hop} from "./LibHop.sol";

interface IRouter1 {
    function swapBalancerV2(Hop calldata h) external payable returns (uint256 amountOut);

    function swapCurve(Hop calldata h) external payable returns (uint256 amountOut);

    function swapDodoV2(Hop calldata h) external payable returns (uint256 amountOut);

    function swapGmx(Hop calldata h) external payable returns (uint256 amountOut);

    function swapHashflow(Hop calldata h) external payable returns (uint256 amountOut);

    function swapIntegralSize(Hop calldata h) external payable returns (uint256 amountOut);

    function swapKyberClassic(Hop calldata h) external payable returns (uint256 amountOut);

    function swapKyberElastic(Hop memory h) external payable returns (uint256 amountOut);

    function swapTrident(Hop calldata h) external payable returns (uint256 amountOut);

    function swapUniswapV2(Hop calldata h) external payable returns (uint256 amountOut);

    function swapUniswapV3V1(Hop calldata h) external payable returns (uint256 amountOut);

    function swapUniswapV3V2(Hop calldata h) external payable returns (uint256 amountOut);

    function swapWooFi(Hop calldata h) external payable returns (uint256 amountOut);

    function swapAlgebra(Hop calldata h) external payable returns (uint256 amountOut);

    function swapSaddle(Hop calldata h) external payable returns (uint256 amountOut);

    function swapWombat(Hop calldata h) external payable returns (uint256 amountOut);

    function swapSolidlyStable(Hop calldata h) external payable returns (uint256 amountOut);

    function swapSolidlyVolatile(Hop calldata h) external payable returns (uint256 amountOut);

    function swapPlatypus(Hop calldata h) external payable returns (uint256 amountOut);

    function swapKokonutBase(Hop calldata h) external payable returns (uint256 amountOut);

    function swapKokonutCrypto(Hop calldata h) external payable returns (uint256 amountOut);

    function swapKokonutMeta(Hop calldata h) external payable returns (uint256 amountOut);

    function swapCamelot(Hop calldata h) external payable returns (uint256 amountOut);

    function swapMantis(Hop calldata h) external payable returns (uint256 amountOut);

    function swapTraderJoeV2_1(Hop calldata h) external payable returns (uint256 amountOut);

    function swapAaveV2(Hop calldata h) external payable returns (uint256 amountOut);
}

