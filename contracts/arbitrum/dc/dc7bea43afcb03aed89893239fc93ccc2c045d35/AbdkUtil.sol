// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ABDKMath64x64} from "./ABDKMath64x64.sol";
import "./SafeCast.sol";

// TODO: refactor into an abstract contract to be inherited by dependent contracts

library AbdkConstants {

}

library Abdk {
    using ABDKMath64x64 for int128;
    using ABDKMath64x64 for uint256;
    using SafeCast for int128;
    using SafeCast for int256;
    using SafeCast for uint256;

    int128 public constant _0_5 = 1 << 63;      // 0.5
    int128 public constant _1 = 1 << 64;        // 1
    int128 public constant _2 = 2 << 64;        // 2
    int128 public constant _3 = 3 << 64;        // 3
    int128 public constant _4 = 4 << 64;        // 4
    int128 public constant _6 = 6 << 64;        // 6
    int128 public constant _8 = 8 << 64;        // 8
    int128 public constant _10 = 10 << 64;      // 10
    int128 public constant _64 = 64 << 64;      // 64
    int128 public constant _100 = 100 << 64;    // 100
    int128 public constant _1000 = 1000 << 64;  // 1000
    int128 public constant _10000 = 10000 << 64;  // 10000

    // TODO: replace this workaround with something prettier
    /**
    * Convert unsigned 256-bit integer number into signed 64.64-bit fixed point
    * number.  Revert on overflow.
    *
    * @param x unsigned 256-bit integer number
    * @return signed 64.64-bit fixed point number
    */
    function toAbdk (uint256 x) internal pure returns (int128) {
        unchecked {
          require (x <= 0x7FFFFFFFFFFFFFFF);
          return int128 (int256 (x << 64));
        }
    }

    // TODO: make an _abdk(uint256) internal pure returns(int128) to be used by descendant contracts

    // TODO: replace this workaround with something prettier
    /**
    * Convert signed 256-bit integer number into signed 64.64-bit fixed point
    * number.  Revert on overflow.
    *
    * @param x signed 256-bit integer number
    * @return signed 64.64-bit fixed point number
    */
    function toAbdk(int256 x) internal pure returns (int128) {
        unchecked {
          require (x >= -0x8000000000000000 && x <= 0x7FFFFFFFFFFFFFFF);
          return int128 (x << 64);
        }
    }

    /// @dev converts argument into 32-bits precision uint256 required to support backend
    function toLowPrecisionUInt(int128 x) internal pure returns(uint256) {
        unchecked {
            require(x >= 0, "AU:WRONG_ARGUMENT");
            return uint256(uint128(x >> 32));
        }
    }

    /// @dev converts argument into 32-bits precision int256 required to support backend
    function toLowPrecisionInt(int128 x) internal pure returns(int256) {
        return int256(x >> 32);
    }

    function min(int128 x, int128 y) internal pure returns(int128) {
        return x < y ? x : y;
    }

    function max(int128 x, int128 y) internal pure returns(int128) {
        return x < y ? y : x;
    }

    function max(uint256 x, uint256 y) internal pure returns(uint256) {
        return x < y ? y : x;
    }

    function toTokenValue(int128 val, uint256 decimals) internal pure returns(uint256) {
        require(val > 0, "AU:CANT_CAST_NEGATIVES");
        return val.muli((10**decimals).toInt256()).toUint256();
    }

    function fromTokenValue(uint256 val, uint256 decimals) internal pure returns(int128) {
        require(decimals < 79, "AU:TOO_MANY_DECIMALS");
        return val.divu(10**decimals);
    }

    // TODO: move CND() to a separate library
    int128 private constant _a1 = int128( 5891549345779789824);      //  0.31938153
    int128 private constant _a2 = int128(-6577440832507964416);      // -0.356563782
    int128 private constant _a3 = int128( 32862467576799068160);     //  1.781477937
    int128 private constant _a4 = int128(-33596242918879592448);     // -1.821255978
    int128 private constant _a5 = int128( 24539231939563106304);     //  1.330274429
    int128 private constant _b1 = int128( 4273038846047820800);      //  0.2316419
    int128 private constant _sqrt_2pi = int128(46239130270042202112);//  2.5066282746310002 == sqrt(2*Pi)

    /**
     * @dev Standard normal cumulative distribution function
     */
    function CND(int128 x) internal pure returns (int128) {
        int128 K = _1.div(x.abs().mul(_b1).add(_1));
        int128 res = _a5.mul(K);
        res = res.add(_a4);
        res = res.mul(K);
        res = res.add(_a3);
        res = res.mul(K);
        res = res.add(_a2);
        res = res.mul(K);
        res = res.add(_a1);
        res = res.mul(K);

        res = x.mul(x).div(_2).neg().exp().mul(res);
        res = res.div(_sqrt_2pi).neg().add(_1);

        return x >= 0 ? res : _1.sub(res);
    }
}

