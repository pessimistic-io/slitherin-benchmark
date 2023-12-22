// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./SafeMath.sol";
import "./SignedSafeMath.sol";

library FixedPoint {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    /// @dev Returns 1 in the fixed point representation, with `self` decimals.
    function unit(uint8 self) internal pure returns (uint256) {
        require(self <= 77, "Too many decimals");
        return 10 ** uint256(self);
    }

    /// @dev Multiplies `self` and `y`, assuming they are both fixed point with 18 digits.
    function muld(uint256 self, uint256 y) internal pure returns (uint256) {
        return muld(self, y, 18);
    }

    /// @dev Multiplies `self` and `y`, assuming they are both fixed point with 18 digits.
    function muld(int256 self, int256 y) internal pure returns (int256) {
        return muld(self, y, 18);
    }

    /// @dev Multiplies `self` and `y`, assuming they are both fixed point with `decimals` digits.
    function muld(uint256 self, uint256 y, uint8 decimals) internal pure returns (uint256) {
        return self.mul(y).div(unit(decimals));
    }

    /// @dev Multiplies `self` and `y`, assuming they are both fixed point with `decimals` digits.
    function muld(int256 self, int256 y, uint8 decimals) internal pure returns (int256) {
        return self.mul(y).div(int256(unit(decimals)));
    }

    /// @dev Divides `self` between `y`, assuming they are both fixed point with 18 digits.
    function divd(uint256 self, uint256 y) internal pure returns (uint256) {
        return divd(self, y, 18);
    }

    /// @dev Divides `self` between `y`, assuming they are both fixed point with 18 digits.
    function divd(int256 self, int256 y) internal pure returns (int256) {
        return divd(self, y, 18);
    }

    /// @dev Divides `self` between `y`, assuming they are both fixed point with `decimals` digits.
    function divd(uint256 self, uint256 y, uint8 decimals) internal pure returns (uint256) {
        return self.mul(unit(decimals)).div(y);
    }

    /// @dev Divides `self` between `y`, assuming they are both fixed point with `decimals` digits.
    function divd(int256 self, int256 y, uint8 decimals) internal pure returns (int256) {
        return self.mul(int256(unit(decimals))).div(y);
    }
}

