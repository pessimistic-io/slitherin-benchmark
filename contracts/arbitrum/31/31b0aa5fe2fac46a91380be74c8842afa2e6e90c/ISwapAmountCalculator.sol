// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISwapAmountCalculator {
    /*
    embedded in User Deposit Liquidity flow

    When increasing liquidity, users can choose token 0 or token 1 to increase liquidity.
    This calculator would take into account the liquidity ratio, price ratio, and pool fee.
    It returns the maximum swap amount for the input token to the other token.
    */
    function calculateMaximumSwapAmountForSingleTokenLiquidityIncrease(
        uint256 liquidityNftId,
        address inputToken,
        uint256 inputAmount
    ) external view returns (uint256 swapAmountWithTradeFee);

    /*
    embedded in Operator/Backend Rescale flow

    When rescaling, a new liquidity NFT can nearly equalize the upper and lower boundaries.
    Thus, it allows for maximum liquidity increase by equal value of token0 and token1.

    When rescaling, there are available two token – dustToken0Amount, dustToken1Amount.
    This calculator would take into account the price ratio, and pool fee.
    It returns the maximum swap amount and direction to equalize the token value.
    */
    function calculateValueEqualizationSwapAmount(
        address poolAddress,
        uint256 token0Amount,
        uint256 token1Amount
    ) external view returns (address swapToken, uint256 swapAmountWithTradeFee);
}

