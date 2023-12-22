// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

/**
 * @title IExchangeSwapWithInQuote
 * @author Souq.Finance
 * @notice Interface for ExchangeSwap contracts
 * @notice License: https://souq-peripherals.s3.amazonaws.com/LICENSE.md
 */

interface IExchangeSwapWithInQuote {
    function swap(address _tokenIn, address _tokenOut, uint256 _amountOut, uint256 _amountInMaximum) external returns (uint256 amountOut);

    function getQuoteIn(address _tokenIn, address _tokenOut, uint256 _amountOut) external returns (uint256 amountInMin);
}

