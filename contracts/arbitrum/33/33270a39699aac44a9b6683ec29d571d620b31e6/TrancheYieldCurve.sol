//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./CoreRef.sol";

contract TrancheYieldCurve is CoreRef {
    using SafeMath for uint256;

    uint256 public seniorProportionTarget1 = 25e16;
    uint256 public seniorProportionTarget2 = 50e16;

    uint256 public m1Numerator = 1;
    uint256 public m1Denominator = 1;
    uint256 public c1Numerator = 0;
    uint256 public c1Denominator = 1;

    uint256 public m2Numerator = 2;
    uint256 public m2Denominator = 5;
    uint256 public c2Numerator = 15e16;
    uint256 public c2Denominator = 1;

    uint256 public m3Numerator = 5;
    uint256 public m3Denominator = 49;
    uint256 public c3Numerator = 1465e16;
    uint256 public c3Denominator = 49;

    constructor(address _core) CoreRef(_core) {}

    function getSeniorYieldDistribution(uint256 _seniorProportion) public view returns(uint256) {
        // y = mx + c
        if (_seniorProportion <= seniorProportionTarget1) {
            return _seniorProportion.mul(m1Numerator).div(m1Denominator).add(c1Numerator.div(c1Denominator));
        } else if (_seniorProportion <= seniorProportionTarget2) {
            return _seniorProportion.mul(m2Numerator).div(m2Denominator).add(c2Numerator.div(c2Denominator));
        } else {
            return _seniorProportion.mul(m3Numerator).div(m3Denominator).add(c3Numerator.div(c3Denominator));
        }
    }

    function setSeniorProportionTarget(uint256 _seniorProportionTarget1, uint256 _seniorProportionTarget2) public onlyTimelock {
        seniorProportionTarget1 = _seniorProportionTarget1;
        seniorProportionTarget2 = _seniorProportionTarget2;
    }

    function setYieldCurve1(uint256 _m1Numerator, uint256 _m1Denominator, uint256 _c1Numerator, uint256 _c1Denominator) public onlyTimelock {
        m1Numerator = _m1Numerator;
        m1Denominator = _m1Denominator;
        c1Numerator = _c1Numerator;
        c1Denominator = _c1Denominator;
    }

    function setYieldCurve2(uint256 _m2Numerator, uint256 _m2Denominator, uint256 _c2Numerator, uint256 _c2Denominator) public onlyTimelock {
        m2Numerator = _m2Numerator;
        m2Denominator = _m2Denominator;
        c2Numerator = _c2Numerator;
        c2Denominator = _c2Denominator;
    }

    function setYieldCurve3(uint256 _m3Numerator, uint256 _m3Denominator, uint256 _c3Numerator, uint256 _c3Denominator) public onlyTimelock {
        m3Numerator = _m3Numerator;
        m3Denominator = _m3Denominator;
        c3Numerator = _c3Numerator;
        c3Denominator = _c3Denominator;
    }

}
