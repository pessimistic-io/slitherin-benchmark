// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./ConstantsLib.sol";

library TokenMath {
    function convertUsdToTokenAmount(
        uint256 usdAmount_,
        uint256 usdExchangeRate_,
        uint8 exchangeRateDecimals_,
        uint256 tokenDecimals_
    ) internal pure returns (uint256 tokenAmount) {
        // usdAmount_ is in USD cents -> normalize to USD_DECIMALS
        uint256 normalizedUsdAmount = usdAmount_ * 10**6;

        // Normalize exchange rate to USD_DECIMALS
        uint256 _usdExchangeRate = exchangeRateDecimals_ >=
            ConstantsLib.USD_DECIMALS
            ? usdExchangeRate_ /
                (10**(exchangeRateDecimals_ - ConstantsLib.USD_DECIMALS))
            : usdExchangeRate_ *
                (10**(ConstantsLib.USD_DECIMALS - exchangeRateDecimals_));

        tokenAmount =
            (normalizedUsdAmount * 10**ConstantsLib.USD_DECIMALS) /
            _usdExchangeRate;

        // Convert token amount to payment token decimals
        tokenAmount = ConstantsLib.USD_DECIMALS > tokenDecimals_
            ? tokenAmount / 10**(ConstantsLib.USD_DECIMALS - tokenDecimals_)
            : tokenAmount * 10**(tokenDecimals_ - ConstantsLib.USD_DECIMALS);
    }
}

