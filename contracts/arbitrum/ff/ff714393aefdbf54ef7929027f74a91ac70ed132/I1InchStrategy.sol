// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IAggregationExecutor.sol";
import "./I1InchRouter.sol";

interface I1InchStrategy {
    // For uniswapV3SwapTo
    struct UniV3SwapTo {
        address payable recipient;
        address srcToken;
        uint256 amount;
        uint256 minReturn;
        uint256[] pools;
    }

    function swap(
        address router,
        IAggregationExecutor executor,
        I1InchRouter.SwapDescription calldata desc,
        bytes calldata permit,
        bytes calldata data
    ) external payable returns (uint256 returnAmount, uint256 spentAmount);

    function uniswapV3Swap(
        address router,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external payable returns (uint256 returnAmount);

    function uniswapV3SwapTo(
        address router,
        UniV3SwapTo calldata uniV3Swap
    ) external payable returns (uint256 returnAmount);

    function uniswapV3SwapToWithPermit(
        address router,
        address payable recipient,
        address srcToken,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools,
        bytes calldata permit
    ) external returns (uint256 returnAmount);
}

