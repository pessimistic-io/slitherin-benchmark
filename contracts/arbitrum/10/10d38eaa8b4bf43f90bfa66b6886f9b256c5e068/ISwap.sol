// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface ISwapGatewayBase {
    function swapExactIn(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        uint24[] memory fees,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactOut(
        uint256 amountOut,
        uint256 amountInMax,
        address[] memory path,
        uint24[] memory fees,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function quoteExactInput(
        uint256 amountIn,
        address[] memory path,
        uint24[] memory fees
    ) external view returns (uint256 amountOut);

    function quoteExactOutput(
        uint256 amountOut,
        address[] memory path,
        uint24[] memory fees
    ) external view returns (uint256 amountIn);
}

interface ISwapGateway {
    function swap(
        address swapRouter,
        uint256 amountIn,
        uint256 amountOut,
        address[] memory path,
        bool isExactInput
    ) external payable returns (uint256[] memory amounts);

    function swap(
        address swapRouter,
        uint256 amountIn,
        uint256 amountOut,
        address[] memory path,
        bool isExactInput,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swap(
        address swapRouter,
        uint256 amountIn,
        uint256 amountOut,
        address[] memory path,
        uint24[] memory fees,
        bool isExactInput
    ) external payable returns (uint256[] memory amounts);

    function swap(
        address swapRouter,
        uint256 amountIn,
        uint256 amountOut,
        address[] memory path,
        uint24[] memory fees,
        bool isExactInput,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function quoteExactInput(
        address swapRouter,
        uint256 amountIn,
        address[] memory path
    ) external view returns (uint256 amountOut);

    function quoteExactInput(
        address swapRouter,
        uint256 amountIn,
        address[] memory path,
        uint24[] memory fees
    ) external view returns (uint256 amountOut);

    function quoteExactOutput(
        address swapRouter,
        uint256 amountOut,
        address[] memory path
    ) external view returns (uint256 amountIn);

    function quoteExactOutput(
        address swapRouter,
        uint256 amountOut,
        address[] memory path,
        uint24[] memory fees
    ) external view returns (uint256 amountIn);
}

