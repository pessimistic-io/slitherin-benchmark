// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import { Math } from "./Math.sol";
import { IntMath } from "./IntMath.sol";
import { UIntMath } from "./UIntMath.sol";

library AmmMath {
    using UIntMath for uint256;
    using IntMath for int256;

    struct BudgetedKScaleCalcParams {
        uint256 quoteAssetReserve;
        uint256 baseAssetReserve;
        int256 budget;
        int256 positionSize;
        uint256 ptcKIncreaseMax;
        uint256 ptcKDecreaseMax;
    }

    /**
     * @notice calculate reserves after repegging with preserving K
     * @dev https://docs.google.com/document/d/1JcKFCFY7vDxys0eWl0K1B3kQEEz-mrr7VU3-JPLPkkE/edit?usp=sharing
     */
    function calcReservesAfterRepeg(
        uint256 _quoteAssetReserve,
        uint256 _baseAssetReserve,
        uint256 _targetPrice,
        int256 _positionSize
    ) internal pure returns (uint256 newQuoteAssetReserve, uint256 newBaseAssetReserve) {
        uint256 spotPrice = _quoteAssetReserve.divD(_baseAssetReserve);
        newQuoteAssetReserve = Math.mulDiv(_baseAssetReserve, Math.sqrt(spotPrice.mulD(_targetPrice)), 1e9);
        newBaseAssetReserve = Math.mulDiv(_baseAssetReserve, Math.sqrt(spotPrice.divD(_targetPrice)), 1e9);
        // in case net user position size is short and its absolute value is bigger than the expected base asset reserve
        if (_positionSize < 0 && newBaseAssetReserve <= _positionSize.abs()) {
            newQuoteAssetReserve = _baseAssetReserve.mulD(_targetPrice);
            newBaseAssetReserve = _baseAssetReserve;
        }
    }

    // function calcBudgetedQuoteReserve(
    //     uint256 _quoteAssetReserve,
    //     uint256 _baseAssetReserve,
    //     int256 _positionSize,
    //     uint256 _budget
    // ) internal pure returns (uint256 newQuoteAssetReserve) {
    //     newQuoteAssetReserve = _positionSize > 0
    //         ? _budget + _quoteAssetReserve + Math.mulDiv(_budget, _baseAssetReserve, _positionSize.abs())
    //         : _budget + _quoteAssetReserve - Math.mulDiv(_budget, _baseAssetReserve, _positionSize.abs());
    // }

    /**
     *@notice calculate the cost for adjusting the reserves
     *@dev
     *For #long>#short (d>0): cost = (y'-x'y'/(x'+d)) - (y-xy/(x+d)) = y'd/(x'+d) - yd/(x+d)
     *For #long<#short (d<0): cost = (xy/(x-|d|)-y) - (x'y'/(x'-|d|)-y') = y|d|/(x-|d|) - y'|d|/(x'-|d|)
     *@param _quoteAssetReserve y
     *@param _baseAssetReserve x
     *@param _positionSize d
     *@param _newQuoteAssetReserve y'
     *@param _newBaseAssetReserve x'
     */

    function calcCostForAdjustReserves(
        uint256 _quoteAssetReserve,
        uint256 _baseAssetReserve,
        int256 _positionSize,
        uint256 _newQuoteAssetReserve,
        uint256 _newBaseAssetReserve
    ) internal pure returns (int256 cost) {
        if (_positionSize > 0) {
            cost =
                (Math.mulDiv(_newQuoteAssetReserve, uint256(_positionSize), (_newBaseAssetReserve + uint256(_positionSize)))).toInt() -
                (Math.mulDiv(_quoteAssetReserve, uint256(_positionSize), (_baseAssetReserve + uint256(_positionSize)))).toInt();
        } else {
            cost =
                (Math.mulDiv(_quoteAssetReserve, uint256(-_positionSize), (_baseAssetReserve - uint256(-_positionSize)), Math.Rounding.Up))
                    .toInt() -
                (
                    Math.mulDiv(
                        _newQuoteAssetReserve,
                        uint256(-_positionSize),
                        (_newBaseAssetReserve - uint256(-_positionSize)),
                        Math.Rounding.Up
                    )
                ).toInt();
        }
    }

    function calculateBudgetedKScale(BudgetedKScaleCalcParams memory params) internal pure returns (uint256, uint256) {
        if (params.positionSize == 0 && params.budget > 0) {
            return (params.ptcKIncreaseMax, 1 ether);
        } else if (params.positionSize == 0 && params.budget < 0) {
            return (params.ptcKDecreaseMax, 1 ether);
        }
        int256 numerator;
        int256 denominator;
        {
            int256 x = params.baseAssetReserve.toInt();
            int256 y = params.quoteAssetReserve.toInt();
            int256 x_d = x + params.positionSize;
            int256 num1 = y.mulD(params.positionSize).mulD(params.positionSize);
            int256 num2 = params.positionSize.mulD(x_d).mulD(params.budget);
            int256 denom2 = x.mulD(x_d).mulD(params.budget);
            int256 denom1 = num1;
            numerator = num1 + num2;
            denominator = denom1 - denom2;
        }
        if (params.budget > 0 && denominator < 0) {
            return (params.ptcKIncreaseMax, 1 ether);
        } else if (params.budget < 0 && numerator < 0) {
            return (params.ptcKDecreaseMax, 1 ether);
        }
        // if (numerator > 0 != denominator > 0 || denominator == 0 || numerator == 0) {
        //     return (_budget > 0 ? params.ptcKIncreaseMax : params.ptcKDecreaseMax, 1 ether);
        // }
        uint256 absNum = numerator.abs();
        uint256 absDen = denominator.abs();
        if (absNum > absDen) {
            uint256 curChange = absNum.divD(absDen);
            uint256 maxChange = params.ptcKIncreaseMax.divD(1 ether);
            if (curChange > maxChange) {
                return (params.ptcKIncreaseMax, 1 ether);
            } else {
                return (absNum, absDen);
            }
        } else {
            uint256 curChange = absNum.divD(absDen);
            uint256 maxChange = params.ptcKDecreaseMax.divD(1 ether);
            if (curChange < maxChange) {
                return (params.ptcKDecreaseMax, 1 ether);
            } else {
                return (absNum, absDen);
            }
        }
    }
}

