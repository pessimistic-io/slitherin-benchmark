// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract CellMath {
    function coordsToCell(
        uint16 y,
        uint16 x
    ) public pure returns (uint32 cell) {
        return (uint32(y) << 16) + x;
    }

    function cellToCoords(
        uint32 cell
    ) public pure returns (uint16 y, uint16 x) {
        return (uint16(cell >> 16), uint16(cell));
    }
}

