// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

import "./IFireBirdStrategy.sol";
import "./IFireBirdRouter.sol";
import "./Withdrawable.sol";

contract FireBirdStrategy is IFireBirdStrategy, Withdrawable {
    //solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function swapExactTokensForTokens(
        address router,
        address tokenIn,
        address tokenOut,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external override returns (uint[] memory amounts) {
        IERC20(tokenIn).approve(router, amountIn);
        return
            IFireBirdRouter(router).swapExactTokensForTokens(
                tokenIn,
                tokenOut,
                amountIn,
                amountOutMin,
                path,
                dexIds,
                to,
                deadline
            );
    }

    function swapExactETHForTokens(
        address router,
        address tokenOut,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external payable override returns (uint[] memory amounts) {
        return
            IFireBirdRouter(router).swapExactETHForTokens{ value: msg.value }(
                tokenOut,
                amountOutMin,
                path,
                dexIds,
                to,
                deadline
            );
    }

    function swapExactTokensForETH(
        address router,
        address tokenIn,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external override returns (uint[] memory amounts) {
        IERC20(tokenIn).approve(router, amountIn);
        return
            IFireBirdRouter(router).swapExactTokensForETH(tokenIn, amountIn, amountOutMin, path, dexIds, to, deadline);
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        address router,
        address tokenIn,
        address tokenOut,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external override {
        IERC20(router).approve(router, amountIn);
        IFireBirdRouter(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenIn,
            tokenOut,
            amountIn,
            amountOutMin,
            path,
            dexIds,
            to,
            deadline
        );
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        address router,
        address tokenOut,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external payable override {
        IFireBirdRouter(router).swapExactETHForTokensSupportingFeeOnTransferTokens{ value: msg.value }(
            tokenOut,
            amountOutMin,
            path,
            dexIds,
            to,
            deadline
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        address router,
        address tokenIn,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external override {
        IERC20(tokenIn).approve(router, amountIn);
        IFireBirdRouter(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenIn,
            amountIn,
            amountOutMin,
            path,
            dexIds,
            to,
            deadline
        );
    }

    function swap(
        address router,
        IAggregationExecutor caller,
        IFireBirdRouter.SwapDescription calldata desc,
        bytes calldata data
    ) external payable override returns (uint256 returnAmount) {
        desc.srcToken.approve(router, desc.amount);
        return IFireBirdRouter(router).swap(caller, desc, data);
    }
}

