// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./CellMath.sol";

/** This contract implements a lookup table for (address x chunk) keys that are
    packed together in a `uint256`.

    coords conversion to chunk IDs is implemented with locality in mind (close
    coordinates are more likely to have the same chunk ID), which helps reduce
    the average cost for painting a large number of cells located closely.

    Lookups return a uint8 value, which means that each lookup key contains
    256/8 = 32 tightly packed `resells` values.
    That's why chunks are of size 4 x 8 = 32.
 */
contract CellMap is CellMath {
    mapping(uint256 => uint256) private _m;

    function toKey(
        address addr,
        uint32 chunk
    ) public pure returns (uint256 key) {
        return (uint256(chunk) << 160) | uint256(uint160(addr));
    }

    function chunkOf(
        uint16 y,
        uint16 x
    ) public pure returns (uint32 chunk, uint8 offsetBits) {
        return (
            // first 16 bits occupied by Y coord of the chunk,
            // second 16 bits occupied by X coord of the chunk
            // equivalent to a tuple (y / 8, x / 4) packed into a single uint32
            (uint32(y >> 3) << 16) | uint32(x >> 2),
            // Find bit offset that corresponds to the coordinates.
            // Since we are dealing with rectangular chunks, coords of
            // (y, x) cell relative to the chunk will be
            //
            //      (yRel, xRel) = (y % WIDTH, x % HEIGHT).
            //
            // So, the absolute bit shift must be (yRel * WIDTH + xRel) * 8.
            (uint8(y % 8) * 4 + uint8(x % 4)) * 8
        );
    }

    function _set(address addr, uint32 cell, uint8 resells) internal {
        (uint16 y, uint16 x) = cellToCoords(cell);
        (uint32 chunk, uint8 offsetBits) = chunkOf(y, x);
        uint256 key = toKey(addr, chunk);
        // mask contains 1s everywhere except of bits we want to update
        uint256 mask = type(uint256).max ^ (0xFF << offsetBits);
        _m[key] = (// overwrite target bits with bits from `resells`
        (uint256(resells) << offsetBits) |
            // overwrite 8 target bits with 0s
            (_m[key] & mask));
    }

    function lookup(
        address addr,
        uint32 cell
    ) public view returns (uint8 resells) {
        (uint16 y, uint16 x) = cellToCoords(cell);
        (uint32 chunk, uint8 offsetBits) = chunkOf(y, x);
        return uint8(_m[toKey(addr, chunk)] >> offsetBits);
    }
}

