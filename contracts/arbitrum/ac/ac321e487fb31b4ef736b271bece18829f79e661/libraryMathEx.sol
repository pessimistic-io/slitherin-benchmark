// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library MathEx {
    uint256 constant MAX_INT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    function computePercentFromNumber(uint256 number, uint256 percent) public pure returns (uint256) {
        return (number * percent) / 100;
    }

    function multiplyWithFloat(
        uint256 number,
        uint256 floatAsDecimal,
        uint256 floatDecimalPlaces
    ) public pure returns (uint256) {
        return (number * floatDecimalPlaces) / floatAsDecimal;
    }
}

