// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { ICamelotPair } from "./ICamelotPair.sol";
import { ICamelotRouter } from "./ICamelotRouter.sol";
import { IChronosFactory } from "./IChronosFactory.sol";
import { IChronosPair } from "./IChronosPair.sol";
import { IChronosRouter } from "./IChronosRouter.sol";
import { ITraderJoeV2Pair } from "./ITraderJoeV2Pair.sol";
import { ITraderJoeV2Router } from "./ITraderJoeV2Router.sol";
import { IUniswapV2Pair } from "./IUniswapV2Pair.sol";
import { IUniswapV2Router } from "./IUniswapV2Router.sol";
import { CamelotLibrary } from "./CamelotLibrary.sol";
import { ChronosLibrary } from "./ChronosLibrary.sol";
import { TraderJoeV2Library } from "./TraderJoeV2Library.sol";
import { UniswapV2Library } from "./UniswapV2Library.sol";

import { Errors } from "./Errors.sol";

library SwapAdapter {
    using CamelotLibrary for ICamelotRouter;
    using ChronosLibrary for IChronosRouter;
    using UniswapV2Library for IUniswapV2Router;
    using TraderJoeV2Library for ITraderJoeV2Router;

    enum DEX {
        None,
        UniswapV2,
        TraderJoeV2,
        Camelot,
        Chronos
    }

    struct PairData {
        address pair;
        bytes data; // Pair specific data such as bin step of TraderJoeV2, pool fee of Uniswap V3, etc.
    }

    struct Setup {
        DEX dex;
        address router;
        PairData pairData;
    }

    function swapExactTokensForTokens(
        Setup memory setup,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path
    ) external returns (uint256 amountOut) {
        if (path[0] == path[path.length - 1]) {
            return amountIn;
        }

        if (setup.dex == DEX.UniswapV2) {
            return
                IUniswapV2Router(setup.router).swapExactTokensForTokens(
                    amountIn,
                    amountOutMin,
                    path
                );
        }

        if (setup.dex == DEX.TraderJoeV2) {
            uint256[] memory binSteps = new uint256[](1);
            binSteps[0] = abi.decode(setup.pairData.data, (uint256));

            return
                ITraderJoeV2Router(setup.router).swapExactTokensForTokens(
                    amountIn,
                    amountOutMin,
                    binSteps,
                    path
                );
        }

        if (setup.dex == DEX.Camelot) {
            return
                ICamelotRouter(setup.router).swapExactTokensForTokens(
                    amountIn,
                    amountOutMin,
                    path
                );
        }

        if (setup.dex == DEX.Chronos) {
            return
                IChronosRouter(setup.router).swapExactTokensForTokens(
                    amountIn,
                    amountOutMin,
                    path
                );
        }

        revert Errors.SwapAdapter_WrongDEX(uint8(setup.dex));
    }

    function swapTokensForExactTokens(
        Setup memory setup,
        uint256 amountOut,
        uint256 amountInMax,
        address[] memory path
    ) external returns (uint256 amountIn) {
        if (path[0] == path[path.length - 1]) {
            return amountOut;
        }

        if (setup.dex == DEX.UniswapV2) {
            return
                IUniswapV2Router(setup.router).swapTokensForExactTokens(
                    amountOut,
                    amountInMax,
                    path
                );
        }

        if (setup.dex == DEX.TraderJoeV2) {
            uint256[] memory binSteps = new uint256[](1);
            binSteps[0] = abi.decode(setup.pairData.data, (uint256));

            return
                ITraderJoeV2Router(setup.router).swapTokensForExactTokens(
                    amountOut,
                    amountInMax,
                    binSteps,
                    path
                );
        }

        if (setup.dex == DEX.Camelot) {
            return
                ICamelotRouter(setup.router).swapTokensForExactTokens(
                    amountOut,
                    amountInMax,
                    path
                );
        }

        if (setup.dex == DEX.Chronos) {
            return
                IChronosRouter(setup.router).swapTokensForExactTokens(
                    amountOut,
                    amountInMax,
                    path
                );
        }

        revert Errors.SwapAdapter_WrongDEX(uint8(setup.dex));
    }

    function getAmountOut(
        Setup memory setup,
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) external view returns (uint256 amountOut) {
        if (tokenIn == tokenOut) {
            return amountIn;
        }

        if (setup.dex == DEX.UniswapV2) {
            return
                IUniswapV2Router(setup.router).getAmountOut(
                    IUniswapV2Pair(setup.pairData.pair),
                    amountIn,
                    tokenIn,
                    tokenOut
                );
        }

        if (setup.dex == DEX.TraderJoeV2) {
            return
                ITraderJoeV2Router(setup.router).getAmountOut(
                    ITraderJoeV2Pair(setup.pairData.pair),
                    amountIn,
                    tokenIn,
                    tokenOut
                );
        }

        if (setup.dex == DEX.Camelot) {
            return
                ICamelotRouter(setup.router).getAmountOut(
                    ICamelotPair(setup.pairData.pair),
                    amountIn,
                    tokenIn
                );
        }

        if (setup.dex == DEX.Chronos) {
            return
                IChronosRouter(setup.router).getAmountOut(
                    IChronosPair(setup.pairData.pair),
                    amountIn,
                    tokenIn
                );
        }

        revert Errors.SwapAdapter_WrongDEX(uint8(setup.dex));
    }

    function getAmountIn(
        Setup memory setup,
        uint256 amountOut,
        address tokenIn,
        address tokenOut
    ) external view returns (uint256 amountIn) {
        if (tokenIn == tokenOut) {
            return amountOut;
        }

        if (setup.dex == DEX.UniswapV2) {
            return
                IUniswapV2Router(setup.router).getAmountIn(
                    IUniswapV2Pair(setup.pairData.pair),
                    amountOut,
                    tokenIn,
                    tokenOut
                );
        }

        if (setup.dex == DEX.TraderJoeV2) {
            return
                ITraderJoeV2Router(setup.router).getAmountIn(
                    ITraderJoeV2Pair(setup.pairData.pair),
                    amountOut,
                    tokenIn,
                    tokenOut
                );
        }

        if (setup.dex == DEX.Camelot) {
            return
                ICamelotRouter(setup.router).getAmountIn(
                    ICamelotPair(setup.pairData.pair),
                    amountOut,
                    tokenOut
                );
        }

        if (setup.dex == DEX.Chronos) {
            address factory = abi.decode(setup.pairData.data, (address));

            return
                IChronosRouter(setup.router).getAmountIn(
                    IChronosPair(setup.pairData.pair),
                    IChronosFactory(factory),
                    amountOut,
                    tokenOut
                );
        }

        revert Errors.SwapAdapter_WrongDEX(uint8(setup.dex));
    }
}

