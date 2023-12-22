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
import "./Math.sol";
import "./ProfitCalculator.sol";

contract HegicStrategyInverseLongCondor is HegicInverseStrategy {
    struct StrategyData4 {
        uint128 amount;
        uint64 sellPutStrike;
        uint64 buyPutStrike;
        uint64 buyCallStrike;
        uint64 sellCallStrike;
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
        uint256 cp = _currentPrice();
        uint256 premium = _calculateStrategyPremium(amount, period);
        StrategyData4 memory sd;

        sd.amount = uint128(amount);
        sd.buyCallStrike = uint64(
            (cp * (PRICE_SCALE_DENOMINATOR + PRICE_SCALE_NUMERATOR)) /
                PRICE_SCALE_DENOMINATOR
        );
        sd.sellCallStrike = uint64(
            sd.buyCallStrike +
                (premium * spotDecimals * 1e8) /
                TOKEN_DECIMALS /
                amount +
                (cp * channelWidth) /
                PRICE_SCALE_DENOMINATOR
        );

        sd.buyPutStrike = uint64(
            (cp * (PRICE_SCALE_DENOMINATOR - PRICE_SCALE_NUMERATOR)) /
                PRICE_SCALE_DENOMINATOR
        );
        sd.sellPutStrike = uint64(
            sd.buyPutStrike -
                (premium * spotDecimals * 1e8) /
                TOKEN_DECIMALS /
                amount -
                (cp * channelWidth) /
                PRICE_SCALE_DENOMINATOR
        );
        strategyData[id] = abi.encode(sd);

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
        StrategyData4 memory data = abi.decode(
            strategyData[optionID],
            (StrategyData4)
        );
        uint256 currentPrice = _currentPrice();
        if (currentPrice < data.sellPutStrike)
            return
                ProfitCalculator.calculatePutProfit(
                    data.buyPutStrike,
                    data.sellPutStrike,
                    data.amount,
                    TOKEN_DECIMALS,
                    spotDecimals,
                    10 ** priceProvider.decimals()
                );
        if (currentPrice < data.buyPutStrike)
            return
                ProfitCalculator.calculatePutProfit(
                    data.buyPutStrike,
                    currentPrice,
                    data.amount,
                    TOKEN_DECIMALS,
                    spotDecimals,
                    10 ** priceProvider.decimals()
                );
        if (currentPrice <= data.buyCallStrike) return 0;
        if (currentPrice < data.sellCallStrike)
            return
                ProfitCalculator.calculateCallProfit(
                    data.buyCallStrike,
                    currentPrice,
                    data.amount,
                    TOKEN_DECIMALS,
                    spotDecimals,
                    10 ** priceProvider.decimals()
                );
        return
            ProfitCalculator.calculateCallProfit(
                data.buyCallStrike,
                data.sellCallStrike,
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
        uint256 cp = _currentPrice();
        uint256 negativePNL = _calculateStrategyPremium(amount, period);

        uint256 buyCallStrike = (cp *
            (PRICE_SCALE_DENOMINATOR + PRICE_SCALE_NUMERATOR)) /
            PRICE_SCALE_DENOMINATOR;
        uint256 sellCallStrike = buyCallStrike +
            (negativePNL * spotDecimals * 1e8) /
            TOKEN_DECIMALS /
            amount +
            (cp * channelWidth) /
            PRICE_SCALE_DENOMINATOR;

        uint256 buyPutStrike = (cp *
            (PRICE_SCALE_DENOMINATOR - PRICE_SCALE_NUMERATOR)) /
            PRICE_SCALE_DENOMINATOR;
        uint256 sellPutStrike = buyPutStrike -
            (negativePNL * spotDecimals * 1e8) /
            TOKEN_DECIMALS /
            amount -
            (cp * channelWidth) /
            PRICE_SCALE_DENOMINATOR;

        uint256 priceDecimals = 10 ** priceProvider.decimals();

        uint256 CALLProfit = ((sellCallStrike - buyCallStrike) *
            amount *
            TOKEN_DECIMALS) /
            spotDecimals /
            priceDecimals;
        uint256 PUTProfit = ((buyPutStrike - sellPutStrike) *
            amount *
            TOKEN_DECIMALS) /
            spotDecimals /
            priceDecimals;
        return uint128(CALLProfit > PUTProfit ? CALLProfit : PUTProfit);
    }
    
    function _getCollateral(
        uint256 positionID
    ) internal view override returns (uint256) {
        StrategyData4 memory data = abi.decode(
            strategyData[positionID],
            (StrategyData4)
        );
        uint256 priceDecimals = 10 ** priceProvider.decimals();

        uint256 CALLProfit = ((data.sellCallStrike - data.buyCallStrike) *
            data.amount *
            TOKEN_DECIMALS) /
            spotDecimals /
            priceDecimals;
        uint256 PUTProfit = ((data.buyPutStrike - data.sellPutStrike) *
            data.amount *
            TOKEN_DECIMALS) /
            spotDecimals /
            priceDecimals;
        return CALLProfit > PUTProfit ? CALLProfit : PUTProfit;
    }
}

