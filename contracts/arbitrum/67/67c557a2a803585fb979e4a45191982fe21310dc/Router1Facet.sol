// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AppStorage} from "./LibMagpieRouter.sol";
import {IRouter1} from "./IRouter1.sol";
import {LibBalancerV2} from "./LibBalancerV2.sol";
import {Hop} from "./LibHop.sol";
import {LibAlgebra} from "./LibAlgebra.sol";
import {LibCurve} from "./LibCurve.sol";
import {LibDodoV2} from "./LibDodoV2.sol";
import {LibGmx} from "./LibGmx.sol";
import {LibHashflow} from "./LibHashflow.sol";
import {LibIntegralSize} from "./LibIntegralSize.sol";
import {LibKyberSwapClassic} from "./LibKyberSwapClassic.sol";
import {LibKyberSwapElastic} from "./LibKyberSwapElastic.sol";
import {LibTrident} from "./LibTrident.sol";
import {LibUniswapV2} from "./LibUniswapV2.sol";
import {LibUniswapV3} from "./LibUniswapV3.sol";
import {LibWooFi} from "./LibWooFi.sol";
import {LibSaddle} from "./LibSaddle.sol";
import {LibWombat} from "./LibWombat.sol";
import {LibSolidly} from "./LibSolidly.sol";
import {LibPlatypus} from "./LibPlatypus.sol";
import {LibKokonutSwap} from "./LibKokonutSwap.sol";
import {LibCamelot} from "./LibCamelot.sol";
import {LibMantisSwap} from "./LibMantisSwap.sol";
import {LibTraderJoeV2_1} from "./LibTraderJoeV2_1.sol";
import {LibAaveV2} from "./LibAaveV2.sol";

contract Router1Facet is IRouter1 {
    AppStorage internal s;

    function swapBalancerV2(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibBalancerV2.swapBalancerV2(h);
    }

    function swapCurve(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibCurve.swapCurve(h);
    }

    function swapDodoV2(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibDodoV2.swapDodoV2(h);
    }

    function swapGmx(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibGmx.swapGmx(h);
    }

    function swapHashflow(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibHashflow.swapHashflow(h);
    }

    function swapIntegralSize(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibIntegralSize.swapIntegralSize(h);
    }

    function swapKyberClassic(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibKyberSwapClassic.swapKyberClassic(h);
    }

    function swapKyberElastic(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibKyberSwapElastic.swapKyberElastic(h);
    }

    function swapTrident(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibTrident.swapTrident(h);
    }

    function swapUniswapV2(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibUniswapV2.swapUniswapV2(h);
    }

    function swapUniswapV3V1(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibUniswapV3.swapUniswapV3V1(h);
    }

    function swapUniswapV3V2(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibUniswapV3.swapUniswapV3V2(h);
    }

    function swapWooFi(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibWooFi.swapWooFi(h);
    }

    function swapAlgebra(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibAlgebra.swapAlgebra(h);
    }

    function swapSaddle(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibSaddle.swapSaddle(h);
    }

    function swapWombat(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibWombat.swapWombat(h);
    }

    function swapSolidlyStable(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibSolidly.swapSolidlyStable(h);
    }

    function swapSolidlyVolatile(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibSolidly.swapSolidlyVolatile(h);
    }

    function swapPlatypus(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibPlatypus.swapPlatypus(h);
    }

    function swapKokonutBase(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibKokonutSwap.swapKokonutBase(h);
    }

    function swapKokonutCrypto(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibKokonutSwap.swapKokonutCrypto(h);
    }

    function swapKokonutMeta(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibKokonutSwap.swapKokonutMeta(h);
    }

    function swapCamelot(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibCamelot.swapCamelot(h);
    }

    function swapMantis(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibMantisSwap.swapMantis(h);
    }

    function swapTraderJoeV2_1(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibTraderJoeV2_1.swapTraderJoeV2_1(h);
    }

    function swapAaveV2(Hop calldata h) external payable returns (uint256 amountOut) {
        return LibAaveV2.swapAaveV2(h);
    }
}

