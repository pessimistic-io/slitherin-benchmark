// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IAggregationExecutor.sol";
import "./IFireBirdRouter.sol";

interface IFireBirdStrategy {
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
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(
        address router,
        address tokenOut,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function swapExactTokensForETH(
        address router,
        address tokenIn,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

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
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        address router,
        address tokenOut,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        address router,
        address tokenIn,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        uint8[] calldata dexIds,
        address to,
        uint deadline
    ) external;

    function swap(
        address router,
        IAggregationExecutor caller,
        IFireBirdRouter.SwapDescription calldata desc,
        bytes calldata data
    ) external payable returns (uint256 returnAmount);
}

