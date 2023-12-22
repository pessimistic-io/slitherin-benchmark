// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

import "./IRateProvider.sol";
import "./IAnkrRatio.sol";
import "./SafeMathUpgradeable.sol";

/**
 *  Inheritable standard rate provider interface.
 */
abstract contract DefaultRateProvider is IRateProvider {
    // --- Wrapper ---
    using SafeMathUpgradeable for uint256;

    // --- Var ---
    address internal s_token;

    // --- Init ---
    constructor(address _token) {
        s_token = _token;
    }

    // --- View ---
    function getRate() external view override returns (uint256) {
        return safeFloorMultiplyAndDivide(1e18, 1e18, IAnkrRatio(s_token).ratio());
    }

    function safeFloorMultiplyAndDivide(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        uint256 remainder = a.mod(c);
        uint256 result = a.div(c);
        bool safe;
        (safe, result) = result.tryMul(b);
        if (!safe) {
            return 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        }
        (safe, result) = result.tryAdd(remainder.mul(b).div(c));
        if (!safe) {
            return 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        }
        return result;
    }
}
