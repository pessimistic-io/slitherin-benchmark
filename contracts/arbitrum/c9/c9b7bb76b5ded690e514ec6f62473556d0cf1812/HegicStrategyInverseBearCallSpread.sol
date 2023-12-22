pragma solidity ^0.8.3;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Hegic
 * Copyright (C) 2022 Hegic Protocol
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

import "./HegicInverseStrategy.sol";
import "./ProfitCalculator.sol";
import "./Math.sol";

contract HegicStrategyInverseBearCallSpread is HegicInverseStrategy {
    uint16 private constant PRICE_SCALE_DENOMINATOR = 1e4;
    uint16[2] private PRICE_SCALE_NUMERATORS;

    constructor(
        AggregatorV3Interface _priceProvider,
        IPremiumCalculator _pricer,
        uint256 _limit,
        uint8 _spotDecimals,
        uint16[2] memory strikeScales,
        uint48[2] memory periodLimits,
        LimitController _limitController
    )
        HegicInverseStrategy(
            _priceProvider,
            _pricer,
            _limit,
            _spotDecimals,
            periodLimits,
            _limitController
        )
    {
        PRICE_SCALE_NUMERATORS = strikeScales;
    }

    function _calculateStrategyPayOff(
        uint256 optionID
    ) internal view override returns (uint256 amount) {
        StrategyData memory data = strategyData[optionID];

        uint256 currentPrice = _currentPrice();

        uint256 strike0 = (data.strike *
            (PRICE_SCALE_DENOMINATOR + PRICE_SCALE_NUMERATORS[0])) /
            PRICE_SCALE_DENOMINATOR;

        uint256 strike1 = (data.strike *
            (PRICE_SCALE_DENOMINATOR + PRICE_SCALE_NUMERATORS[1])) /
            PRICE_SCALE_DENOMINATOR;

        return
            currentPrice > strike1
                ? ProfitCalculator.calculateCallProfit(
                    strike0,
                    strike1,
                    data.amount,
                    TOKEN_DECIMALS,
                    spotDecimals,
                    10 ** priceProvider.decimals()
                )
                : ProfitCalculator.calculateCallProfit(
                    strike0,
                    currentPrice,
                    data.amount,
                    TOKEN_DECIMALS,
                    spotDecimals,
                    10 ** priceProvider.decimals()
                );
    }

    function _calculateCollateral(
        uint256 amount,
        uint256 /*period*/
    ) internal view override returns (uint128 collateral) {
        uint256 currentPrice = _currentPrice();

        uint256 strike0 = (currentPrice *
            (PRICE_SCALE_DENOMINATOR + PRICE_SCALE_NUMERATORS[0])) /
            PRICE_SCALE_DENOMINATOR;

        uint256 strike1 = (currentPrice *
            (PRICE_SCALE_DENOMINATOR + PRICE_SCALE_NUMERATORS[1])) /
            PRICE_SCALE_DENOMINATOR;

        return
            uint128(
                ProfitCalculator.calculateCallProfit(
                    strike0,
                    strike1,
                    amount,
                    TOKEN_DECIMALS,
                    spotDecimals,
                    10 ** priceProvider.decimals()
                )
            );
    }
}

