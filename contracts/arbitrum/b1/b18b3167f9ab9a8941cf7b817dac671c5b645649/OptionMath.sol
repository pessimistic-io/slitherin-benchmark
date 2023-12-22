// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ABDKMath64x64.sol";
import "./ABDKMath64x64Token.sol";

/**
 * @title Option Math Helper Library
 */

library OptionMath {
    using ABDKMath64x64 for int128;
    using ABDKMath64x64 for uint256;
    using ABDKMath64x64Token for int128;
    using ABDKMath64x64Token for uint256;

    int256 private constant ONE = 10000000000000000000;

    struct Value {
        int256 value;
        int256 ruler;
    }

    /**
     * @custom:author Yaojin Sun
     * @notice applies ceiling to the second highest place value of a positive 64x64 fixed point number
     * @param x 64x64 fixed point number
     * @return rounded 64x64 fixed point number
     */
    function ceil64x64(int128 x) internal pure returns (int128) {
        require(x > 0);

        (int256 integer, Value[3] memory values) = _getPositivePlaceValues(x);

        // if the summation of first and second values is equal to integer, the integer has already been rounded
        if (
            values[0].ruler *
                values[0].value +
                values[1].ruler *
                values[1].value ==
            integer
        ) {
            return int128((integer << 64) / ONE);
        }

        return
            int128(
                (((values[0].ruler * values[0].value) +
                    (values[1].ruler * (values[1].value + 1))) << 64) / ONE
            );
    }

    /**
     * @custom:author Yaojin Sun
     * @notice applies floor to the second highest place value of a positive 64x64 fixed point number
     * @param x 64x64 fixed point number
     * @return rounded 64x64 fixed point number
     */
    function floor64x64(int128 x) internal pure returns (int128) {
        require(x > 0);

        (, Value[3] memory values) = _getPositivePlaceValues(x);

        // No matter whether third value is non-zero or not, we ONLY need to keep the first and second places.
        int256 res =
            (values[0].ruler * values[0].value) +
                (values[1].ruler * values[1].value);
        return int128((res << 64) / ONE);
    }

    function _getPositivePlaceValues(int128 x)
        private
        pure
        returns (int256, Value[3] memory)
    {
        // move the decimal part to integer by multiplying 10...0
        int256 integer = (int256(x) * ONE) >> 64;

        // scan and identify the highest position
        int256 ruler = 100000000000000000000000000000000000000; // 10^38
        while (integer < ruler) {
            ruler = ruler / 10;
        }

        Value[3] memory values;

        // find the first/second/third largest places and there value
        values[0] = Value(0, 0);
        values[1] = Value(0, 0);
        values[2] = Value(0, 0);

        // setup the first place value
        values[0].ruler = ruler;
        if (values[0].ruler != 0) {
            values[0].value = (integer / values[0].ruler) % 10;

            // setup the second place value
            values[1].ruler = ruler / 10;
            if (values[1].ruler != 0) {
                values[1].value = (integer / values[1].ruler) % 10;

                // setup the third place value
                values[2].ruler = ruler / 100;
                if (values[2].ruler != 0) {
                    values[2].value = (integer / values[2].ruler) % 10;
                }
            }
        }

        return (integer, values);
    }

    /**
     * @notice converts the value to the base token amount
     * @param underlyingDecimals decimal precision of the underlying asset
     * @param baseDecimals decimal precision of the base asset
     * @param value amount to convert
     * @return decimal representation of base token amount
     */
    function toBaseTokenAmount(
        uint8 underlyingDecimals,
        uint8 baseDecimals,
        uint256 value
    ) internal pure returns (uint256) {
        int128 value64x64 = value.fromDecimals(underlyingDecimals);
        return value64x64.toDecimals(baseDecimals);
    }

    /**
     * @notice calculates the collateral asset amount from the number of contracts
     * @param isCall option type, true if call option
     * @param underlyingDecimals decimal precision of the underlying asset
     * @param baseDecimals decimal precision of the base asset
     * @param strike64x64 strike price of the option as 64x64 fixed point number
     * @return collateral asset amount
     */
    function fromContractsToCollateral(
        uint256 contracts,
        bool isCall,
        uint8 underlyingDecimals,
        uint8 baseDecimals,
        int128 strike64x64
    ) internal pure returns (uint256) {
        if (strike64x64 == 0) {
            return 0;
        }

        if (isCall) {
            return contracts;
        }

        return
            toBaseTokenAmount(
                underlyingDecimals,
                baseDecimals,
                strike64x64.mulu(contracts)
            );
    }

    /**
     * @notice calculates number of contracts from the collateral asset amount
     * @param isCall option type, true if call option
     * @param baseDecimals decimal precision of the base asset
     * @param strike64x64 strike price of the option as 64x64 fixed point number
     * @return number of contracts
     */
    function fromCollateralToContracts(
        uint256 collateral,
        bool isCall,
        uint8 baseDecimals,
        int128 strike64x64
    ) internal pure returns (uint256) {
        if (strike64x64 == 0) {
            return 0;
        }

        if (isCall) {
            return collateral;
        }

        int128 collateral64x64 = collateral.fromDecimals(baseDecimals);
        return collateral64x64.div(strike64x64).toDecimals(baseDecimals);
    }
}

