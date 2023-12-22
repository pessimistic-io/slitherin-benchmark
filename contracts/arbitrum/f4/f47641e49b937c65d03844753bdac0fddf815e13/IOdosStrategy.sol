//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IOdosRouter.sol";

interface IOdosStrategy {
    function swapCompact(
        address router,
        IOdosRouter.swapTokenInfo memory tokenInfo,
        bytes calldata data
    ) external payable returns (uint256);

    function swap(
        address router,
        IOdosRouter.swapTokenInfo memory tokenInfo,
        bytes calldata pathDefinition,
        address executor,
        uint32 referralCode
    ) external payable returns (uint256 amountOut);

    function swapMulti(
        address router,
        IOdosRouter.inputTokenInfo[] memory inputs,
        IOdosRouter.outputTokenInfo[] memory outputs,
        uint256 valueOutMin,
        bytes calldata pathDefinition,
        address executor,
        uint32 referralCode
    ) external payable returns (uint256[] memory amountsOut);
}

