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
    struct StrategyData2 {
        uint128 amount;
        uint64 strike1;
        uint64 strike2;
    }

    constructor(
        AggregatorV3Interface _priceProvider,
        IPremiumCalculator _pricer,
        uint256 _limit,
        uint8 _spotDecimals,
        uint16[2] memory scales,
        uint48[2] memory periodLimits,
        LimitController _limitController
    )
        HegicInverseStrategy(
            _priceProvider,
            _pricer,
            _limit,
            _spotDecimals,
            scales,
            periodLimits,
            _limitController
        )
    {}

    function _create(
        uint256 id,
        address holder,
        uint256 amount,
        uint256 period,
        bytes[] calldata additional
    )
        internal
        override
        returns (uint32 expiration, uint256 negativePNL, uint256 positivePNL)
    {
        uint256 premium = _calculateStrategyPremium(amount, period);
        uint256 cp = _currentPrice();
        uint256 s1 = (cp * (PRICE_SCALE_DENOMINATOR + PRICE_SCALE_NUMERATOR)) /
            PRICE_SCALE_DENOMINATOR;
        uint256 s2 = s1 +
            (premium * spotDecimals * 1e8) /
            TOKEN_DECIMALS /
            amount +
            (cp * channelWidth) /
            PRICE_SCALE_DENOMINATOR;

        strategyData[id] = abi.encode(
            StrategyData2(uint128(amount), uint64(s1), uint64(s2))
        );
        return
            HegicInverseStrategy._create(
                id,
                holder,
                amount,
                period,
                additional
            );
    }

    function _calculateStrategyPayOff(
        uint256 optionID
    ) internal view override returns (uint256 amount) {
        StrategyData2 memory data = abi.decode(
            strategyData[optionID],
            (StrategyData2)
        );
        uint currentPrice = _currentPrice();

        return
            currentPrice > data.strike2
                ? ProfitCalculator.calculateCallProfit(
                    data.strike1,
                    data.strike2,
                    data.amount,
                    TOKEN_DECIMALS,
                    spotDecimals,
                    10 ** priceProvider.decimals()
                )
                : ProfitCalculator.calculateCallProfit(
                    data.strike1,
                    currentPrice,
                    data.amount,
                    TOKEN_DECIMALS,
                    spotDecimals,
                    10 ** priceProvider.decimals()
                );
    }

    function _calculateCollateral(
        uint256 amount,
        uint256 period
    ) internal view override returns (uint128 collateral) {
        uint256 negativePNL = _calculateStrategyPremium(amount, period);

        uint256 cp = _currentPrice();
        uint256 s1 = (cp * (PRICE_SCALE_DENOMINATOR + PRICE_SCALE_NUMERATOR)) /
            PRICE_SCALE_DENOMINATOR;
        uint256 s2 = s1 +
            (negativePNL * spotDecimals * 1e8) /
            TOKEN_DECIMALS /
            amount +
            (cp * channelWidth) /
            PRICE_SCALE_DENOMINATOR;

        return
            uint128(
                ProfitCalculator.calculateCallProfit(
                    s1,
                    s2,
                    amount,
                    TOKEN_DECIMALS,
                    spotDecimals,
                    10 ** priceProvider.decimals()
                )
            );
    }

    function _getCollateral(
        uint256 positionID
    ) internal view override returns (uint256) {
        StrategyData2 memory data = abi.decode(
            strategyData[positionID],
            (StrategyData2)
        );
        return
            ProfitCalculator.calculateCallProfit(
                data.strike1,
                data.strike2,
                data.amount,
                TOKEN_DECIMALS,
                spotDecimals,
                10 ** priceProvider.decimals()
            );
    }
}

