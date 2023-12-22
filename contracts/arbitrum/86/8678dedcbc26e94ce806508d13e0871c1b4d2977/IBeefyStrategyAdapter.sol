// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

interface IBeefyStrategyAdapter {
    function addLiquidity(
        address token,
        uint256 amount,
        uint256 minMintAmount
    ) external returns (uint256);

    function removeLiquidity(
        address token,
        uint256 lpAmount,
        uint256 minAmountOut
    ) external returns (uint256[2] memory);

    function removeLiquidityOneCoin(
        address token,
        uint256 lpTokenAmount,
        uint256 minAmountOut
    ) external returns (uint256);
}

