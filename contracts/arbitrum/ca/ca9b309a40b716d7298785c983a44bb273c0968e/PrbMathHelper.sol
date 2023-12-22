pragma solidity >=0.8.19;

import {UD60x18, mul as mulUD60x18} from "./UD60x18.sol";
import {SD59x18, mul as mulSD59x18} from "./SD59x18.sol";
import "./SafeCast.sol";

using SafeCastU256 for uint256;
using SafeCastI256 for int256;

/// @notice Multiplies an unsigned wad number by an
/// unsigned number. Result's precision is given by
/// the unsigned number's precision.
/// @param a denotes the unsigned wad number
/// @param b denotes the unsigned number whose precision
/// determines the precision of the result
function mulUDxUint(UD60x18 a, uint256 b) pure returns (uint256) {
    return UD60x18.unwrap(mulUD60x18(a, UD60x18.wrap(b)));
}

/// @notice Multiplies an unsigned wad number by a
/// signed number. Result's precision is given by
/// the signed number's precision.
/// @param a denotes the unsigned wad number
/// @param b denotes the signed number whose precision
/// determines the precision of the result
function mulUDxInt(UD60x18 a, int256 b) pure returns (int256) {
    return mulSDxUint(SD59x18.wrap(b), UD60x18.unwrap(a));
}

/// @notice Multiplies a signed wad number by a
/// signed number. Result's precision is given by
/// the signed number's precision.
/// @param a denotes the signed wad number
/// @param b denotes the signed number whose precision
/// determines the precision of the result
function mulSDxInt(SD59x18 a, int256 b) pure returns (int256) {
    return SD59x18.unwrap(mulSD59x18(a, SD59x18.wrap(b)));
}

/// @notice Multiplies a signed wad number by an
/// unsigned number. Result's precision is given by
/// the unsigned number's precision.
/// @param a denotes the signed wad number
/// @param b denotes the unsigned number whose precision
/// determines the precision of the result
function mulSDxUint(SD59x18 a, uint256 b) pure returns (int256) {
    return SD59x18.unwrap(mulSD59x18(a, SD59x18.wrap(b.toInt())));
}

/// @dev Safely casts a `SD59x18` to a `UD60x18`. Reverts on overflow.
function ud60x18(SD59x18 sd) pure returns (UD60x18 ud) {
    return UD60x18.wrap(SD59x18.unwrap(sd).toUint());
}

/// @dev Safely casts a `UD60x18` to a `SD59x18`. Reverts on overflow.
function sd59x18(UD60x18 ud) pure returns (SD59x18 sd) {
    return SD59x18.wrap(UD60x18.unwrap(ud).toInt());
}

