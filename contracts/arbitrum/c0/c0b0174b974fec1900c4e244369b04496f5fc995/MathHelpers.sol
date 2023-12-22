// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {SafeMath} from "./SafeMath.sol";

/**
 * @title library for the math helper functions
 * @author Souq.Finance
 * @notice Defines the math helper functions common throughout the protocol
 * @notice License: https://souq-exchange.s3.amazonaws.com/LICENSE.md
 */
library MathHelpers {
    using SafeMath for uint256;

    function convertToWad(uint256 x) internal pure returns (uint256 z) {
        z = x.mul(10 ** 18);
    }

    function convertFromWad(uint256 x) internal pure returns (uint256 z) {
        z = x.div(10 ** 18);
    }

    function convertFromWadToDecimal(uint256 x, uint256 decimals) internal pure returns (uint256 z)
    {
        z = x.div(10 ** (18 - decimals));
    }

    function convertFromBiggerToSmaller(uint256 x, uint256 from, uint256 to) internal pure returns (uint256 z)
    {
        z = x.div(10 ** (from - to));
    }

    function convertToWadPercentage(uint256 x) internal pure returns (uint256 z) {
        z = x.mul(10 ** 20);
    }

    function convertFromWadPercentage(uint256 x) internal pure returns (uint256 z) {
        z = x.div(10 ** 20);
    }
}
