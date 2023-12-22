// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.0;

/**
 * @dev Library for managing uint256 to uint16 mapping in a compact and efficient way, providing the keys are sequential.
 * The code is based on OpenZeppelin BitMaps implementation https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/structs/BitMaps.sol
 * It might be easily converted to any multiple uint* type by replacing uint16 with that type and correspondingly tuning the INT_* constants.
 * A multiple types should divide 256 without remaining, i.e 1 (BitMap),2,4,8,16,32,64 & 128
 * Technically it's possible to use this library for store not multiple int types, but it requires much more complicated logic.
 */
library Uint16Maps {
    /**
     * @dev Int type size in bits.
     * Modify it if you want to adopt this map to other uint* type
     */
    uint private constant INT_BITS = 16;
    uint private constant INT_TIMES = 256 / INT_BITS;
    /**
     * @dev How many bits required to present INT_TIMES in binary format.
     * Modify it if you want to adopt this map to other uint* type
     */
    uint private constant INT_BITS_SHIFT = 4;
    uint private constant INT_BITS_MASK = INT_TIMES - 1;

    struct BitMap {
        mapping(uint256 => uint256) _data;
    }

    /**
     * @dev Returns whether the uint16 at `index` is set.
     */
    function get(BitMap storage bitmap, uint256 index) internal view returns (uint16) {
        // the same as index / INT_TIMES
        uint256 bucket = index >> INT_BITS_SHIFT;
        // the same as index % INT_TIMES * INT_BITS
        uint256 offset = (index & INT_BITS_MASK) * INT_BITS;
        uint256 mask = INT_BITS_MASK << offset;
        return uint16((bitmap._data[bucket] & mask) >> offset);
    }

    /**
     * @dev Sets the bit at `index` to the boolean `value`.
     */
    function setTo(BitMap storage bitmap, uint256 index, uint16 value) internal {
        // the same as index / INT_TIMES
        uint256 bucket = index >> INT_BITS_SHIFT;
        // the same as index % INT_TIMES * INT_BITS
        uint256 offset = (index & INT_BITS_MASK) * INT_BITS;

        // ...111100..0011111... where zeroes are a place into which we will put the value.
        uint256 mask = INT_BITS_MASK << offset;
        uint256 oldValue = bitmap._data[bucket];
        // oldValue & ~mask - fills with zeroes slot for the value
        // | (uint256(value) << offset) - sets the value into the slot
        uint256 newValue = (oldValue & ~mask) | (uint256(value) << offset);

        bitmap._data[bucket] = newValue;
    }
}
