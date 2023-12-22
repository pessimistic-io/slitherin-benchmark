// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./PositionInfo.sol";
import "./ProxyCallerApi.sol";
import "./IPriceOracle.sol";
import "./IERC20Decimals.sol";
import "./IExchangeAdapter.sol";

library PositionExchangeLib {
    using ProxyCallerApi for ProxyCaller;

    uint public constant POSITION_PRICE_LIMITS_MULTIPLIER = 1e8;
    uint public constant SLIPPAGE_MULTIPLIER = 1e8;

    function isPriceOutsideRange(PositionInfo memory position, IPriceOracle oracle) public view returns (bool) {
        if (address(oracle) == address(0)) return false;

        uint oracleMultiplier = 10**oracle.decimals();
        uint oraclePrice = uint(oracle.latestAnswer());

        // oraclePriceFloat = oraclePrice / oracleMultiplier
        // stopLossPriceFloat = position.stopLossPrice / POSITION_PRICE_LIMITS_MULTIPLIER
        // if
        // oraclePrice / oracleMultiplier > position.stopLossPrice / POSITION_PRICE_LIMITS_MULTIPLIER
        // then
        // oraclePrice * POSITION_PRICE_LIMITS_MULTIPLIER > position.stopLossPrice * oracleMultiplier

        if (
            position.stopLossPrice != 0 &&
            oraclePrice * POSITION_PRICE_LIMITS_MULTIPLIER < position.stopLossPrice * oracleMultiplier
        ) return true;

        if (
            position.takeProfitPrice != 0 &&
            oraclePrice * POSITION_PRICE_LIMITS_MULTIPLIER > position.takeProfitPrice * oracleMultiplier
        ) return true;

        return false;
    }

    // swapToStable works only if price oracle exists
    function swapTo(
        PositionInfo memory position,
        IPriceOracle oracle,
        IExchangeAdapter tokenExchange,
        address tokenOut,
        uint amount
    ) external {
        uint oracleMultiplier = 10**oracle.decimals();
        uint oraclePrice = uint(oracle.latestAnswer());

        // Optimistic conversion stablecoin amount
        uint minAmountOut = (amount * oraclePrice) / oracleMultiplier;
        {
            // Accounting slippage
            minAmountOut = minAmountOut - (minAmountOut * position.maxSlippage) / SLIPPAGE_MULTIPLIER;
            // Scale according to tokens decimals
            uint8 tokenInDecimals = IERC20Decimals(address(position.stakedToken)).decimals();
            uint8 tokenOutDecimals = IERC20Decimals(tokenOut).decimals();

            // Check for bigger one to avoid int overflow while multiplying
            if (tokenInDecimals > tokenOutDecimals) {
                minAmountOut = minAmountOut / 10**(tokenInDecimals - tokenOutDecimals);
            } else if (tokenOutDecimals > tokenInDecimals) {
                minAmountOut = minAmountOut / 10**(tokenOutDecimals - tokenInDecimals);
            }
        }
        position.callerAddress.swapExactTokensForTokens(
            tokenExchange, // adapter
            address(position.stakedToken), // tokenIn
            tokenOut, // tokenOut
            amount, // amountIn
            minAmountOut, // amountOutMin
            position.owner, // to
            block.timestamp // deadline
        );
    }
}

