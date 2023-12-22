// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {WadRayMath} from "./WadRayMath.sol";
import {DataTypes} from "./DataTypes.sol";

/**
 * @title DebtMath library
 * @author Tazz Labs
 * @notice Provides approximations for Perpetual Debt calculations
 */
library DebtMath {
    using WadRayMath for uint256;

    //returns approximation of rate = -beta * ln(price)
    //Taylor expansion as per whitepaper
    function calculateApproxRate(uint256 _beta, uint256 _price) internal pure returns (int256 rate_) {
        //separate calculation depending on whether (1-_price) is positive or negative
        if (_price <= WadRayMath.ray()) {
            uint256 rate1 = WadRayMath.ray() - _price;
            uint256 rate2 = rate1.rayMul(rate1);
            uint256 rate3 = rate2.rayMul(rate1);
            uint256 rate4 = rate2.rayMul(rate2);
            uint256 rate5 = rate3.rayMul(rate2);
            uint256 rate6 = rate3.rayMul(rate3);

            rate1 = rate1 + rate2 / 2 + rate3 / 3 + rate4 / 4 + rate5 / 5 + rate6 / 6;
            rate_ = int256(rate1.rayMul(_beta));
        } else {
            uint256 rate1 = _price - WadRayMath.ray();
            uint256 rate2 = rate1.rayMul(rate1);
            uint256 rate3 = rate2.rayMul(rate1);
            uint256 rate4 = rate2.rayMul(rate2);
            uint256 rate5 = rate3.rayMul(rate2);
            uint256 rate6 = rate3.rayMul(rate3);

            rate1 = rate1 - rate2 / 2 + rate3 / 3 - rate4 / 4 + rate5 / 5 - rate6 / 6;
            rate_ = -int256(rate1.rayMul(_beta));
        }
    }

    //Taylor expansion to calculate compounding rate update as per whitepaper
    function calculateApproxNotionalUpdate(int256 _rate, uint256 _timeDelta)
        internal
        pure
        returns (uint256 updateMultiplier_)
    {
        _rate = _rate * int256(_timeDelta);
        if (_rate >= 0) {
            uint256 rate1 = uint256(_rate);
            uint256 rate2 = rate1.rayMul(rate1) / 2;
            uint256 rate3 = rate2.rayMul(rate1) / 3;
            updateMultiplier_ = WadRayMath.ray() + rate1 + rate2 + rate3;
        } else {
            uint256 rate1 = uint256(-_rate);
            uint256 rate2 = rate1.rayMul(rate1) / 2;
            uint256 rate3 = rate2.rayMul(rate1) / 3;
            updateMultiplier_ = WadRayMath.ray() - rate1 + rate2 - rate3;
        }
    }
}

