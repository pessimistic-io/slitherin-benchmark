// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/** This contract implements a specialized (x, y) => bool mapping that uses
    storage optimally (1 bit per cell).
 */
contract CoordSet {
    uint8 public immutable CHUNK_SIZE = 4;

    mapping(uint32 => uint256) private owners;

    // Close cells are likely to be in the same chunk
    function coordsToChunk(
        uint16 y,
        uint16 x
    ) public pure returns (uint32 chunk, uint8 offsetBits) {
        return (
            (uint32(y / CHUNK_SIZE) << 16) | uint32(x / CHUNK_SIZE),
            // calculate offset in bits relative to chunk start.
            (uint8(y % CHUNK_SIZE) * CHUNK_SIZE + uint8(x % CHUNK_SIZE)) << 3
        );
    }

    function _setCoords(uint16 y, uint16 x) internal {
        (uint32 chunk, uint8 offsetBits) = coordsToChunk(y, x);
        owners[chunk] = owners[chunk] | (1 << offsetBits);
    }

    function getCoords(uint16 y, uint16 x) public view returns (bool) {
        (uint32 chunk, uint8 offsetBits) = coordsToChunk(y, x);
        uint256 bitmap = owners[chunk];
        return (bitmap >> offsetBits) & 1 == 1;
    }
}

