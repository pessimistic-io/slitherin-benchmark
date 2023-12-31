//SPDX-License-Identifier: agpl-3.0
pragma solidity =0.7.6;

import "./Math.sol";

/**
 * @title MathTester
 * @notice Tester contract for Math library
 */
contract MathTester {
    function testAddDelta(uint256 _x, int256 _y) external pure returns (uint256) {
        return Math.addDelta(_x, _y);
    }

    function testMulDiv(
        int256 _x,
        int256 _y,
        int256 _d,
        bool _roundUp
    ) external pure returns (int256) {
        return Math.mulDiv(_x, _y, _d, _roundUp);
    }

    function testScale(
        uint256 _a,
        uint256 _from,
        uint256 _to
    ) external pure returns (uint256) {
        return Math.scale(_a, _from, _to);
    }

    function testLog(uint256 _x) external pure returns (int256) {
        return Math.log(_x);
    }

    function testExp(int256 _x) external pure returns (uint256) {
        return Math.exp(_x);
    }
}

