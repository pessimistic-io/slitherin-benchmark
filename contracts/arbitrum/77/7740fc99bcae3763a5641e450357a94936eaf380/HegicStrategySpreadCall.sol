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

import "./ProfitCalculator.sol";
import "./HegicStrategy.sol";

contract HegicStrategySpreadCall is HegicStrategy {
    uint16 private constant PRICE_SCALE_DENOMINATOR = 1e4;
    uint16[2] private PRICE_SCALE_NUMERATORS;

    constructor(
        AggregatorV3Interface _priceProvider,
        IPremiumCalculator _pricer,
        uint256 _limit,
        uint8 _spotDecimals,
        uint16[2] memory _priceScales,
        uint48[2] memory periodLimits,
        uint48 _exerciseWindowDuration,
        LimitController _limitController
    )
        HegicStrategy(
            _priceProvider,
            _pricer,
            _limit,
            _spotDecimals,
            periodLimits,
            _exerciseWindowDuration,
            _limitController
        )
    {
        PRICE_SCALE_NUMERATORS = _priceScales;
    }
    
    function _calculateStrategyPayOff(uint256 optionID)
        internal
        view
        override
        returns (uint256 amount)
    {
        StrategyData memory data = abi.decode(strategyData[optionID], (StrategyData));

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
                    10**priceProvider.decimals()
                )
                : ProfitCalculator.calculateCallProfit(
                    strike0,
                    currentPrice,
                    data.amount,
                    TOKEN_DECIMALS,
                    spotDecimals,
                    10**priceProvider.decimals()
                );
    }
}

