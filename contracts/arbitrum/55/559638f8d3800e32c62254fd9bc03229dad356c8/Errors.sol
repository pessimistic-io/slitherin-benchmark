// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

library Errors {
    // IndexStrategyUpgradeable errors.
    error Index_NotWhitelistedToken(address token);
    error Index_ExceedEquityValuationLimit();
    error Index_TooSmallAmountIndex();
    error Index_AboveMaxAmount();
    error Index_BelowMinAmount();
    error Index_ZeroAddress();
    error Index_WrongSwapAmount();
    error Index_WrongPair(address tokenIn, address tokenOut);

    // SwapAdapter errors.
    error SwapAdapter_WrongDEX(uint8 dex);
    error SwapAdapter_WrongPair(address tokenIn, address tokenOut);

    // IndexOracle errors.
    error Oracle_TokenNotSupported(address token);
}

