// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IZap {

    event Deposited(
        address user,
        address vault,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1,
        uint256 lpAmount
    );

    event Withdrawn(
        address user,
        address vault,
        uint256 shareamount,
        uint256 amount0,
        uint256 amount1
    );
    
    function zapInSingle(
        address vault,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin
    ) external payable;

    function zapInDual(
        address vault,
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    ) external payable;

    function zapOut(address vault, uint256 amount) external;

    function zapOutAndSwap(
        address vault,
        uint256 amount,
        address desiredToken,
        uint256 desiredTokenOutMin
    ) external;
}

