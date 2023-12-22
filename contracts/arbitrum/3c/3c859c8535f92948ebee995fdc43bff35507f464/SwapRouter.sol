// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {CamelotSwapper} from "./CamelotSwapper.sol";
import {SushiSwapper} from "./SushiSwapper.sol";
import {UniswapV3Swapper} from "./UniswapV3Swapper.sol";
import {IErrors} from "./IErrors.sol";
import {IRouter} from "./IRouter.sol";

/// @title SwapRouter
/// @notice A contract that swaps tokens on selected DEX
contract SwapRouter is IRouter, UniswapV3Swapper {
    function swap(
        PathRoute memory path,
        uint256 amount,
        address receiver
    ) external returns (uint256 amountOut) {
        if (path.route == 1) {
            amountOut = CamelotSwapper._swapOnCamelot(
                path.bestPath,
                amount,
                path.toAmountMin,
                receiver
            );
        } else if (path.route == 2) {
            amountOut = SushiSwapper._swapOnSushi(
                path.bestPath,
                amount,
                path.toAmountMin,
                receiver
            );
        } else if (path.route == 3) {
            amountOut = _swapOnUniswapV3(
                path.bestPath,
                path.fee,
                amount,
                path.toAmountMin,
                receiver
            );
        } else revert IErrors.InvalidPath();
    }
}

