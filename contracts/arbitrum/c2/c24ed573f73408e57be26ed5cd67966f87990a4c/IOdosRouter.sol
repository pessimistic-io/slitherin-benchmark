// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IOdosRouter {
    struct inputToken {
        address tokenAddress;
        uint256 amountIn;
        address receiver;
        bytes permit;
    }

    struct outputToken {
        address tokenAddress;
        uint256 relativeValue;
        address receiver;
    }

    event Swapped(
        address sender,
        uint256[] amountsIn,
        address[] tokensIn,
        uint256[] amountsOut,
        outputToken[] outputs,
        uint256 valueOutQuote
    );

    function swap(
        inputToken[] memory inputs,
        outputToken[] memory outputs,
        uint256 valueOutQuote,
        uint256 valueOutMin,
        address executor,
        bytes calldata pathDefinition
    ) external payable returns (uint256[] memory amountsOut, uint256 gasLeft);

    function transferFunds(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address dest
    ) external;
}

