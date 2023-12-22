// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

using {
    shiftBytes,
    shiftBytes32,
    shiftAddress,
    shiftUint160,
    shiftUint40,
    shiftUint32,
    shiftUint24,
    shiftUint8
} for CalldataCursor global;

struct CalldataCursor {
    uint256 offset; // in bytes
    uint256 maxOffset; // in bytes
}

/// @dev Returns right-aligned value
/// @param cursor Calldata cursor
/// @param size Size of the value in bytes. Assuming the given value must be <=32.
function shift(CalldataCursor memory cursor, uint256 size) pure returns (uint256 value) {
    require(cursor.offset + size <= cursor.maxOffset, "Calldata: out of bounds");
    assembly ("memory-safe") {
        value := shr(sub(256, mul(8, size)), calldataload(mload(cursor)))
    }
    unchecked {
        cursor.offset += size;
    }
}

function shiftBytes(CalldataCursor memory cursor, uint256 size) pure returns (bytes memory value) {
    require(cursor.offset + size <= cursor.maxOffset, "Calldata: out of bounds");
    value = new bytes(size);
    assembly ("memory-safe") {
        calldatacopy(add(value, 32), mload(cursor), size)
    }
    unchecked {
        cursor.offset += size;
    }
}

function shiftBytes32(CalldataCursor memory cursor) pure returns (bytes32 value) {
    return bytes32(shift(cursor, 32));
}

function shiftAddress(CalldataCursor memory cursor) pure returns (address value) {
    return address(uint160(shift(cursor, 20)));
}

function shiftUint160(CalldataCursor memory cursor) pure returns (uint160 value) {
    return uint160(shift(cursor, 20));
}

function shiftUint40(CalldataCursor memory cursor) pure returns (uint40 value) {
    return uint40(shift(cursor, 5));
}

function shiftUint32(CalldataCursor memory cursor) pure returns (uint32 value) {
    return uint32(shift(cursor, 4));
}

function shiftUint24(CalldataCursor memory cursor) pure returns (uint24 value) {
    return uint24(shift(cursor, 3));
}

function shiftUint8(CalldataCursor memory cursor) pure returns (uint8 value) {
    return uint8(shift(cursor, 1));
}

