// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { FixedPoint96 } from "./FixedPoint96.sol";
import { FullMath } from "./FullMath.sol";
import { PerpSafeCast } from "./PerpSafeCast.sol";
import { SafeMathUpgradeable } from "./SafeMathUpgradeable.sol";
import { SignedSafeMathUpgradeable } from "./SignedSafeMathUpgradeable.sol";

library PerpMath {
    // CONST
    int256 internal constant _IQ96 = 0x1000000000000000000000000;

    using PerpSafeCast for int256;
    using PerpSafeCast for uint256;
    using PerpMath for int256;
    using SignedSafeMathUpgradeable for int256;
    using SafeMathUpgradeable for uint256;

    function formatSqrtPriceX96ToPriceX96(uint160 sqrtPriceX96) internal pure returns (uint256) {
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }

    function formatX10_18ToX96(uint256 valueX10_18) internal pure returns (uint256) {
        return FullMath.mulDiv(valueX10_18, FixedPoint96.Q96, 1 ether);
    }

    function formatX96ToX10_18(uint256 valueX96) internal pure returns (uint256) {
        return FullMath.mulDiv(valueX96, 1 ether, FixedPoint96.Q96);
    }

    function max(int256 a, int256 b) internal pure returns (int256) {
        return a >= b ? a : b;
    }

    function min(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function abs(int256 value) internal pure returns (uint256) {
        return value >= 0 ? value.toUint256() : neg256(value).toUint256();
    }

    function neg256(int256 a) internal pure returns (int256) {
        require(a > -2 ** 255, "PerpMath: inversion overflow");
        return -a;
    }

    function neg256(uint256 a) internal pure returns (int256) {
        return -PerpSafeCast.toInt256(a);
    }

    function neg128(int128 a) internal pure returns (int128) {
        require(a > -2 ** 127, "PerpMath: inversion overflow");
        return -a;
    }

    function neg128(uint128 a) internal pure returns (int128) {
        return -PerpSafeCast.toInt128(a);
    }

    function divBy10_18(int256 value) internal pure returns (int256) {
        // no overflow here
        return value / (1 ether);
    }

    function divBy10_18(uint256 value) internal pure returns (uint256) {
        // no overflow here
        return value / (1 ether);
    }

    function subRatio(uint24 a, uint24 b) internal pure returns (uint24) {
        require(b <= a, "PerpMath: subtraction overflow");
        return a - b;
    }

    function mulRatio(uint256 value, uint24 ratio) internal pure returns (uint256) {
        return FullMath.mulDiv(value, ratio, 1e6);
    }

    function mulRatio(int256 value, uint24 ratio) internal pure returns (int256) {
        return mulDiv(value, int256(ratio), 1e6);
    }

    function divRatio(uint256 value, uint24 ratio) internal pure returns (uint256) {
        return FullMath.mulDiv(value, 1e6, ratio);
    }

    /// @param denominator cannot be 0 and is checked in FullMath.mulDiv()
    function mulDiv(int256 a, int256 b, uint256 denominator) internal pure returns (int256 result) {
        uint256 unsignedA = a < 0 ? uint256(neg256(a)) : uint256(a);
        uint256 unsignedB = b < 0 ? uint256(neg256(b)) : uint256(b);
        bool negative = ((a < 0 && b > 0) || (a > 0 && b < 0)) ? true : false;

        uint256 unsignedResult = FullMath.mulDiv(unsignedA, unsignedB, denominator);

        result = negative ? neg256(unsignedResult) : PerpSafeCast.toInt256(unsignedResult);

        return result;
    }

    function mulMultiplier(int256 value, uint256 multiplier) internal pure returns (int256) {
        return mulDiv(value, int256(multiplier), 1e18);
    }

    function divMultiplier(int256 value, uint256 multiplier) internal pure returns (int256) {
        return mulDiv(value, 1e18, multiplier);
    }

    function mulMultiplier(uint256 value, uint256 multiplier) internal pure returns (uint256) {
        return FullMath.mulDiv(value, multiplier, 1e18);
    }

    function divMultiplier(uint256 value, uint256 multiplier) internal pure returns (uint256) {
        return FullMath.mulDiv(value, 1e18, multiplier);
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
        // else z = 0 (default value)
    }

    function formatPriceX10_18ToSqrtPriceX96(uint256 y) internal pure returns (uint160) {
        uint256 z;
        z = formatX10_18ToX96(y);
        z = z.mul(FixedPoint96.Q96);
        z = sqrt(z);
        return PerpSafeCast.toUint160(z);
    }

    uint256 internal constant _ONE_HUNDRED_PERCENT = 1e6; // 100%

    //
    // INTERNAL PURE
    //

    function calcAmountScaledByFeeRatio(
        uint256 amount,
        uint24 feeRatio,
        bool isScaledUp
    ) internal pure returns (uint256) {
        // when scaling up, round up to avoid imprecision; it's okay as long as we round down later
        return
            isScaledUp
                ? FullMath.mulDivRoundingUp(amount, _ONE_HUNDRED_PERCENT, uint256(_ONE_HUNDRED_PERCENT).sub(feeRatio))
                : FullMath.mulDiv(amount, uint256(_ONE_HUNDRED_PERCENT).sub(feeRatio), _ONE_HUNDRED_PERCENT);
    }

    /// @return scaledAmountForUniswapV3PoolSwap the unsigned scaled amount for UniswapV3Pool.swap()
    /// @return signedScaledAmountForReplaySwap the signed scaled amount for _replaySwap()
    /// @dev for UniswapV3Pool.swap(), scaling the amount is necessary to achieve the custom fee effect
    /// @dev for _replaySwap(), however, as we can input ExchangeFeeRatioRatio directly in SwapMath.computeSwapStep(),
    ///      there is no need to stick to the scaled amount
    /// @dev refer to CH._openPosition() docstring for explainer diagram
    function calcScaledAmountForSwaps(
        bool isBaseToQuote,
        bool isExactInput,
        uint256 amount,
        uint24 uniswapFeeRatio
    ) internal pure returns (uint256 scaledAmountForUniswapV3PoolSwap, int256 signedScaledAmountForReplaySwap) {
        if (isBaseToQuote) {
            scaledAmountForUniswapV3PoolSwap = isExactInput
                ? calcAmountScaledByFeeRatio(amount, uniswapFeeRatio, true)
                : calcAmountScaledByFeeRatio(amount, 0, true);
        } else {
            scaledAmountForUniswapV3PoolSwap = isExactInput
                ? calcAmountWithFeeRatioReplaced(amount, uniswapFeeRatio, 0, true)
                : amount;
        }

        // x : uniswapFeeRatio, y : exchangeFeeRatioRatio
        // since we can input ExchangeFeeRatioRatio directly in SwapMath.computeSwapStep() in _replaySwap(),
        // when !isBaseToQuote, we can use the original amount directly
        // ex: when x(uniswapFeeRatio) = 1%, y(exchangeFeeRatioRatio) = 3%, input == 1 quote
        // our target is to get fee == 0.03 quote
        // if scaling the input as 1 * 0.97 / 0.99, the fee calculated in `_replaySwap()` won't be 0.03
        signedScaledAmountForReplaySwap = isBaseToQuote
            ? scaledAmountForUniswapV3PoolSwap.toInt256()
            : amount.toInt256();
        signedScaledAmountForReplaySwap = isExactInput
            ? signedScaledAmountForReplaySwap
            : signedScaledAmountForReplaySwap.neg256();
    }

    /// @param isReplacingUniswapFeeRatio is to replace uniswapFeeRatio or clearingHouseFeeRatio
    ///        let x : uniswapFeeRatio, y : clearingHouseFeeRatio
    ///        true: replacing uniswapFeeRatio with clearingHouseFeeRatio: amount * (1 - y) / (1 - x)
    ///        false: replacing clearingHouseFeeRatio with uniswapFeeRatio: amount * (1 - x) / (1 - y)
    ///        multiplying a fee is applying it as the new standard and dividing a fee is removing its effect
    /// @dev calculate the amount when feeRatio is switched between uniswapFeeRatio and clearingHouseFeeRatio
    function calcAmountWithFeeRatioReplaced(
        uint256 amount,
        uint24 uniswapFeeRatio,
        uint24 clearingHouseFeeRatio,
        bool isReplacingUniswapFeeRatio
    ) internal pure returns (uint256) {
        (uint24 newFeeRatio, uint24 replacedFeeRatio) = isReplacingUniswapFeeRatio
            ? (clearingHouseFeeRatio, uniswapFeeRatio)
            : (uniswapFeeRatio, clearingHouseFeeRatio);

        return
            FullMath.mulDivRoundingUp(
                amount,
                uint256(_ONE_HUNDRED_PERCENT).sub(newFeeRatio),
                uint256(_ONE_HUNDRED_PERCENT).sub(replacedFeeRatio)
            );
    }

    function lte(
        uint256 settlementToken,
        // solhint-disable-next-line var-name-mixedcase
        uint256 amountX10_18,
        uint8 decimals
    ) internal pure returns (bool) {
        return parseSettlementToken(settlementToken, decimals) <= amountX10_18;
    }

    function lte(
        int256 settlementToken,
        // solhint-disable-next-line var-name-mixedcase
        int256 amountX10_18,
        uint8 decimals
    ) internal pure returns (bool) {
        return parseSettlementToken(settlementToken, decimals) <= amountX10_18;
    }

    function lt(
        uint256 settlementToken,
        // solhint-disable-next-line var-name-mixedcase
        uint256 amountX10_18,
        uint8 decimals
    ) internal pure returns (bool) {
        return parseSettlementToken(settlementToken, decimals) < amountX10_18;
    }

    function lt(
        int256 settlementToken,
        // solhint-disable-next-line var-name-mixedcase
        int256 amountX10_18,
        uint8 decimals
    ) internal pure returns (bool) {
        return parseSettlementToken(settlementToken, decimals) < amountX10_18;
    }

    function gt(
        uint256 settlementToken,
        // solhint-disable-next-line var-name-mixedcase
        uint256 amountX10_18,
        uint8 decimals
    ) internal pure returns (bool) {
        return parseSettlementToken(settlementToken, decimals) > amountX10_18;
    }

    function gt(
        int256 settlementToken,
        // solhint-disable-next-line var-name-mixedcase
        int256 amountX10_18,
        uint8 decimals
    ) internal pure returns (bool) {
        return parseSettlementToken(settlementToken, decimals) > amountX10_18;
    }

    function gte(
        uint256 settlementToken,
        // solhint-disable-next-line var-name-mixedcase
        uint256 amountX10_18,
        uint8 decimals
    ) internal pure returns (bool) {
        return parseSettlementToken(settlementToken, decimals) >= amountX10_18;
    }

    function gte(
        int256 settlementToken,
        // solhint-disable-next-line var-name-mixedcase
        int256 amountX10_18,
        uint8 decimals
    ) internal pure returns (bool) {
        return parseSettlementToken(settlementToken, decimals) >= amountX10_18;
    }

    // returns number with 18 decimals
    function parseSettlementToken(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        return amount.mul(10 ** (18 - decimals));
    }

    // returns number with 18 decimals
    function parseSettlementToken(int256 amount, uint8 decimals) internal pure returns (int256) {
        return amount.mul(int256(10 ** (18 - decimals)));
    }

    // returns number converted from 18 decimals to settlementToken's decimals
    function formatSettlementToken(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        return amount.div(10 ** (18 - decimals));
    }

    // returns number converted from 18 decimals to settlementToken's decimals
    // will always round down no matter positive value or negative value
    function formatSettlementToken(int256 amount, uint8 decimals) internal pure returns (int256) {
        uint256 denominator = 10 ** (18 - decimals);
        int256 rounding = 0;
        if (amount < 0 && uint256(-amount) % denominator != 0) {
            rounding = -1;
        }
        return amount.div(int256(denominator)).add(rounding);
    }
}

