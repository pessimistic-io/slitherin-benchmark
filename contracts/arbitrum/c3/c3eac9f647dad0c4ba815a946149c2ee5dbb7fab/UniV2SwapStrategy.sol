// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IUniV2Strategy.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Router01.sol";
import "./Withdrawable.sol";

contract UniV2SwapStrategy is Withdrawable, IUniV2Strategy {
    receive() external payable {}

    function swapExactTokensForTokens(
        address router,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external override {
        IERC20(path[0]).approve(router, amountIn);
        try
            IUniswapV2Router02(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMin,
                path,
                to,
                deadline
            )
        {} catch {
            IUniswapV2Router01(router).swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
        }
    }

    function swapExactETHForTokens(
        address router,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable override {
        try
            IUniswapV2Router02(router).swapExactETHForTokensSupportingFeeOnTransferTokens{ value: msg.value }(
                amountOutMin,
                path,
                to,
                deadline
            )
        {} catch {
            IUniswapV2Router01(router).swapExactETHForTokens{ value: msg.value }(amountOutMin, path, to, deadline);
        }
    }

    function swapExactTokensForETH(
        address router,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external override {
        IERC20(path[0]).approve(router, amountIn);
        try
            IUniswapV2Router02(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMin,
                path,
                to,
                deadline
            )
        {} catch {
            IUniswapV2Router01(router).swapExactTokensForETH(amountIn, amountOutMin, path, to, deadline);
        }
    }

    function getAmountsOut(
        address router,
        uint amountIn,
        address[] calldata path
    ) external view override returns (uint[] memory amounts) {
        return IUniswapV2Router01(router).getAmountsOut(amountIn, path);
    }
}

