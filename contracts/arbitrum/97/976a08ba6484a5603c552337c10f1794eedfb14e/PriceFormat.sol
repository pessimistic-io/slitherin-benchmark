// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0 <0.9.0;

import "./TickMath.sol";
import "./Logarithm.sol";

library PriceFormat {
    function getInitialRate(
        uint128 _crowdFundingRate,
        uint16  _etherToLiquidityPercent,
        uint16  _tokenToLiquidityPercent,
        uint128 _limitPerMint
    ) internal pure returns(uint) {
        // return _crowdFundingRate * _etherToLiquidityPercent * (10000 - _tokenToLiquidityPercent) * 10**14 / _tokenToLiquidityPercent / _limitPerMint;
        // To avoid the result is zero, the params must satisfy the following condition:
        // _crowdFundingRate * 10**18 > _limitPerMint
        uint128 precision = 10**12;
        return (_crowdFundingRate / precision) * _etherToLiquidityPercent * (10000 - _tokenToLiquidityPercent) * 10**14 / _tokenToLiquidityPercent / (_limitPerMint / precision);
    }

    function tickToSqrtPriceX96(int24 _tick) internal pure returns(uint160) {
        return TickMath.getSqrtRatioAtTick(_tick);
    }

    function priceToTick(int256 _price, int24 _tickSpace) internal pure returns(int24) {
        // math.log(10**18,2) * 10**18 = 59794705707972520000
        // math.log(1.0001,2) * 10**18 = 144262291094538
        return round((Logarithm.log2(_price * 1e18, 1e18, 5e17) - 59794705707972520000 ), (int(144262291094538) * _tickSpace)) * _tickSpace;
    }

    function priceToSqrtPriceX96(int256 _price, int24 _tickSpace) internal pure returns(uint160) {
        return tickToSqrtPriceX96(priceToTick(_price, _tickSpace));
    }

    function round(int256 _a, int256 _b) internal pure returns(int24) {
        return int24(10000 * _a / _b % 10000 > 10000 / 2 ? _a / _b + 1 : _a / _b);
    }
}
