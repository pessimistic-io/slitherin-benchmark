// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "./IERC20Minimal.sol";
import "./ISwapRouter.sol";
import "./IUniV3Strategy.sol";
import "./Withdrawable.sol";

contract UniV3SwapStrategy is IUniV3Strategy, Withdrawable {
    receive() external payable {}

    function exactInputSingle(
        address router,
        ISwapRouter.ExactInputSingleParams calldata params
    ) external payable override returns (uint256 amountOut) {
        if (params.tokenIn != address(0)) IERC20Minimal(params.tokenIn).approve(router, params.amountIn);
        amountOut = ISwapRouter(router).exactInputSingle{ value: msg.value }(params);
    }

    function exactInput(
        address router,
        ISwapRouter.ExactInputParams calldata params
    ) external payable override returns (uint256 amountOut) {
        amountOut = ISwapRouter(router).exactInput{ value: msg.value }(params);
    }

    function exactOutputSingle(
        address router,
        ISwapRouter.ExactOutputSingleParams calldata params
    ) external payable override returns (uint256 amountOut) {
        amountOut = ISwapRouter(router).exactOutputSingle{ value: msg.value }(params);
    }

    function exactOutput(
        address router,
        ISwapRouter.ExactOutputParams calldata params
    ) external payable override returns (uint256 amountOut) {
        amountOut = ISwapRouter(router).exactOutput{ value: msg.value }(params);
    }
}

