// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./IUniswapV3Pool.sol";
import "./TickMath.sol";
import "./FixedPointMathLib.sol";
import "./Constants.sol";

library SwapLib {
    struct SwapUnderlyingParams {
        int256 amountPerp;
        int256 amountSqrtPerp;
        int256 fee;
    }

    struct SwapStableResult {
        int256 amountPerp;
        int256 amountSqrtPerp;
        int256 fee;
    }

    uint256 constant UNDERLYING_ONE = 1e18;

    /**
     * @notice
     * @param _swapParams Plus means In, Minus means Out
     * @return swapResult Plus means Out, Minus means In
     */
    function swap(address _uniswapPool, SwapUnderlyingParams memory _swapParams, bool _isMarginZero)
        internal
        returns (SwapStableResult memory swapResult)
    {
        int256 amountUnderlying = _swapParams.amountPerp + _swapParams.amountSqrtPerp + _swapParams.fee;

        if (_swapParams.amountPerp == 0 && _swapParams.amountSqrtPerp == 0 && _swapParams.fee == 0) {
            return SwapStableResult(0, 0, 0);
        }

        if (amountUnderlying == 0) {
            (uint160 currentSqrtPrice,,,,,,) = IUniswapV3Pool(_uniswapPool).slot0();

            int256 amountStable = int256(calculateStableAmount(currentSqrtPrice, UNDERLYING_ONE, _isMarginZero));

            return divToStable(_swapParams, int256(UNDERLYING_ONE), amountStable, 0);
        } else {
            bool zeroForOne;

            if (amountUnderlying > 0) {
                // exactIn
                zeroForOne = !_isMarginZero;
            } else {
                zeroForOne = _isMarginZero;
            }

            (int256 amount0, int256 amount1) = IUniswapV3Pool(_uniswapPool).swap(
                address(this),
                zeroForOne,
                // + means exactIn, - means exactOut
                amountUnderlying,
                (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
                ""
            );

            int256 amountStable;
            if (_isMarginZero) {
                amountStable = -amount0;
            } else {
                amountStable = -amount1;
            }

            return divToStable(_swapParams, amountUnderlying, amountStable, amountStable);
        }
    }

    function calculateStableAmount(uint160 _currentSqrtPrice, uint256 _underlyingAmount, bool _isMarginZero)
        internal
        pure
        returns (uint256)
    {
        if (_isMarginZero) {
            uint256 stableAmount = (_currentSqrtPrice * _underlyingAmount) >> Constants.RESOLUTION;

            return (stableAmount * _currentSqrtPrice) >> Constants.RESOLUTION;
        } else {
            uint256 stableAmount = (_underlyingAmount * Constants.Q96) / _currentSqrtPrice;

            return stableAmount * Constants.Q96 / _currentSqrtPrice;
        }
    }

    function divToStable(
        SwapUnderlyingParams memory _swapParams,
        int256 _amountUnderlying,
        int256 _amountStable,
        int256 _totalAmountStable
    ) internal pure returns (SwapStableResult memory swapResult) {
        // TODO: calculate trade price
        swapResult.amountPerp = _amountStable * _swapParams.amountPerp / _amountUnderlying;
        swapResult.amountSqrtPerp = _amountStable * _swapParams.amountSqrtPerp / _amountUnderlying;
        swapResult.fee = _totalAmountStable - swapResult.amountPerp - swapResult.amountSqrtPerp;
    }
}

