// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ISwapRouter.sol";

interface IUniV3Strategy {
    function exactInputSingle(
        address router,
        ISwapRouter.ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);

    function exactInput(
        address router,
        ISwapRouter.ExactInputParams calldata params
    ) external payable returns (uint256 amountOut);

    function exactOutputSingle(
        address router,
        ISwapRouter.ExactOutputSingleParams calldata params
    ) external payable returns (uint256 amountOut);

    function exactOutput(
        address router,
        ISwapRouter.ExactOutputParams calldata params
    ) external payable returns (uint256 amountOut);
}

