pragma solidity 0.8.6;

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

import "./HegicStrategy.sol";
import "./Interfaces.sol";

contract HegicStrategyStrangle is HegicStrategy {
    using SafeERC20 for IERC20;
    // uint256 private immutable spotDecimals; // 1e18
    uint256 private constant TOKEN_DECIMALS = 1e6; // 1e6
    uint256 public strikePercentage;
    uint8 internal roundedDecimals;

    constructor(
        IHegicOperationalTreasury _pool,
        AggregatorV3Interface _priceProvider,
        IPremiumCalculator _pricer,
        uint8 _spotDecimals,
        uint256 limit,
        uint256 percentage,
        uint8 _roundedDecimals
    ) HegicStrategy(_pool, _priceProvider, _pricer, 10, limit, _spotDecimals) {
        strikePercentage = percentage;
        roundedDecimals = _roundedDecimals;
    }

    function _profitOf(uint256 optionID)
        internal
        view
        override
        returns (uint256 amount)
    {
        StrategyData memory data = strategyData[optionID];
        uint256 currentPrice = _currentPrice();
        uint256 priceDecimals = 10**priceProvider.decimals();
        uint256 callStrike =
            round(
                (data.strike * (100 + strikePercentage)) / 100,
                roundedDecimals
            );
        uint256 putStrike =
            round(
                (data.strike * (100 - strikePercentage)) / 100,
                roundedDecimals
            );
        if (currentPrice > callStrike) {
            return
                ((currentPrice - callStrike) * data.amount * TOKEN_DECIMALS) /
                spotDecimals /
                priceDecimals;
        } else if (currentPrice < putStrike) {
            return
                ((putStrike - currentPrice) * data.amount * TOKEN_DECIMALS) /
                spotDecimals /
                priceDecimals;
        }
        return 0;
    }

    /**
     * @notice Used for buying options/strategies
     * @param holder The holder address
     * @param period The option/strategy period
     * @param amount The option/strategy amount
     * @param strike The option/strategy strike
     **/
    function buy(
        address holder,
        uint32 period,
        uint128 amount,
        uint256 strike
    ) external override nonReentrant returns (uint256 id) {
        if (strike == 0) strike = _currentPrice();
        uint256 premium = _calculatePremium(period, amount, strike);
        uint128 lockedAmount = _calculateLockedAmount(amount, period, strike);
        uint256 callStrike =
            round((strike * (100 + strikePercentage)) / 100, roundedDecimals);
        uint256 putStrike =
            round((strike * (100 - strikePercentage)) / 100, roundedDecimals);

        require(
            pool.lockedByStrategy(address(this)) + lockedAmount <= lockedLimit,
            "HegicStrategy: The limit is exceeded"
        );

        pool.token().safeTransferFrom(msg.sender, address(pool), premium);

        uint32 expiration = uint32(block.timestamp + period);
        id = pool.lockLiquidityFor(holder, lockedAmount, expiration);
        strategyData[id] = StrategyData(uint128(amount), uint128(strike));
        emit AcquiredStrangle(
            id,
            amount,
            premium,
            callStrike,
            putStrike,
            expiration
        );
    }

    function round(uint256 value, uint8 decimals)
        public
        pure
        returns (uint256 roundedValue)
    {
        uint256 a = value / 10**(decimals - 1);
        if (a % 10 < 5) return (a / 10) * 10**decimals;
        return (a / 10 + 1) * 10**decimals;
    }
}

