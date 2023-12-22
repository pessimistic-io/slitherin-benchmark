// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {AppStorage} from "./LibMagpieAggregator.sol";
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
import {LibWoofi} from "./LibWoofi.sol";
import {LibSaddle} from "./LibSaddle.sol";

contract Router1Facet is IRouter1 {
    AppStorage internal s;

    function swapBalancerV2(Hop calldata h) external payable {
        LibBalancerV2.swapBalancerV2(h);
    }

    function swapCurve(Hop calldata h) external payable {
        LibCurve.swapCurve(h);
    }

    function swapDodoV2(Hop calldata h) external payable {
        LibDodoV2.swapDodoV2(h);
    }

    function swapGmx(Hop calldata h) external payable {
        LibGmx.swapGmx(h);
    }

    function swapHashflow(Hop calldata h) external payable {
        LibHashflow.swapHashflow(h);
    }

    function swapIntegralSize(Hop calldata h) external payable {
        LibIntegralSize.swapIntegralSize(h);
    }

    function swapKyberClassic(Hop calldata h) external payable {
        LibKyberSwapClassic.swapKyberClassic(h);
    }

    function swapKyberElastic(Hop calldata h) external payable {
        LibKyberSwapElastic.swapKyberElastic(h);
    }

    function swapTrident(Hop calldata h) external payable {
        LibTrident.swapTrident(h);
    }

    function swapUniswapV2(Hop calldata h) external payable {
        LibUniswapV2.swapUniswapV2(h);
    }

    function swapUniswapV3(Hop calldata h) external payable {
        LibUniswapV3.swapUniswapV3(h);
    }

    function swapWoofi(Hop calldata h) external payable {
        LibWoofi.swapWoofi(h);
    }

    function swapAlgebra(Hop calldata h) external payable {
        LibAlgebra.swapAlgebra(h);
    }

    function swapSaddle(Hop calldata h) external payable {
        LibSaddle.swapSaddle(h);
    }
}

