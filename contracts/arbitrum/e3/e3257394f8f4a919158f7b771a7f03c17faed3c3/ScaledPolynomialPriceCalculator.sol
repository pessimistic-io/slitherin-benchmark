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

import "./Interfaces.sol";
import "./Math.sol";
import "./ScaledStrikePriceCalculator.sol";

contract ScaledPolynomialPriceCalculator is ScaledStrikePriceCalculator {
    using HegicMath for uint256;

    int256[5] public discont;
    IPremiumCalculator public basePricer;
    uint256 internal immutable discontDecimals = 1e30;

    event SetDiscont(int256[5] values);

    constructor(
        uint256 _priceCorrectionRate,
        uint8 _roundedDecimals,
        IPremiumCalculator _basePricer,
        int256[5] memory initialDiscont
    )
        ScaledStrikePriceCalculator(
            _basePricer.priceProvider(),
            _priceCorrectionRate,
            _roundedDecimals
        )
    {
        discont = initialDiscont;
        basePricer = _basePricer;
    }

    /**
     * @notice Used for adjusting the options prices (the premiums)
     * @param values [i] New setDiscont value
     **/
    function setDiscont(int256[5] calldata values) external onlyOwner {
        discont = values;
        emit SetDiscont(values);
    }

    function _calculatePeriodFee(
        uint256 period,
        uint256 amount,
        uint256 strike
    ) internal view virtual override returns (uint256 discontPremium) {
        uint256 premium = basePricer.calculatePremium(period, amount, strike);
        uint256 calculatedDiscont =
            uint256(
                discont[0] +
                    discont[1] *
                    int256(period) +
                    discont[2] *
                    int256(period)**2 +
                    discont[3] *
                    int256(period)**3 +
                    discont[4] *
                    int256(period)**4
            );
        return (premium * calculatedDiscont) / discontDecimals;
    }
}

