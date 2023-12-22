// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IERC20Detailed} from "./IERC20Detailed.sol";
import {FullMath} from "./FullMath.sol";
import {TickMath} from "./TickMath.sol";

/**
 * @title X96Math library
 * @author Tazz Labs
 * @notice Math conversion for sqrt X96 ratios used by Uniswap
 */
library X96Math {
    //@Dev - asset price returned in money units (with money Decimal places)
    function getPriceFromSqrtX96(
        address moneyToken,
        address assetToken,
        uint160 sqrtRatioX96
    ) internal view returns (uint256 price_) {
        uint256 baseDecimals = IERC20Detailed(assetToken).decimals();
        uint256 baseAmount = 10**baseDecimals;
        return quoteFromSqrtPriceX96(baseAmount, sqrtRatioX96, assetToken, moneyToken);
    }

    //@dev code from https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/OracleLibrary.sol, getQuoteaTick function
    // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
    function quoteFromSqrtPriceX96(
        uint256 baseAmount,
        uint160 sqrtPriceX96,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint256 quoteAmount) {
        if (sqrtPriceX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }
}

