// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./IVRFStorage.sol";

library Random {
    error DeltaIsOutOfRange(uint8 got, uint8 max);
    uint8 internal constant BYTES_IN_WORD = 32;

    struct Seed {
        uint seed;
        uint8 pointer;
    }

    function _remain(Seed memory seed) private pure returns (uint8) {
        return BYTES_IN_WORD - seed.pointer;
    }

    function _upgradeSeed(Seed memory seed) private pure {
        seed.seed = uint(keccak256(abi.encode(seed.seed)));
        seed.pointer = 0;
    }

    function _mask(uint8 size) private pure returns (uint) {
        return type(uint).max >> (256 - (size << 3));
    }

    function _read(Seed memory seed, uint8 count, uint8 offset) private pure returns (uint) {
        // >> (8 * count), than result << (offset * 8)
        uint result = (seed.seed >> (seed.pointer << 3)) << (offset << 3);
        return result & _mask(count + offset);
    }

    function _get(Seed memory seed, uint8 delta) private pure returns (uint) {
        if (delta > BYTES_IN_WORD) {
            revert DeltaIsOutOfRange(delta, BYTES_IN_WORD);
        }

        uint result = 0;
        if (delta > _remain(seed)) {
            uint8 remain = _remain(seed);
            delta -= remain;

            result = _read(seed, remain, delta);
            _upgradeSeed(seed);
        }

        result |= _read(seed, delta, 0);
        seed.pointer += delta;

        return result;
    }

    function get8(Seed memory seed) internal pure returns (uint8) {
        return uint8(_get(seed, 1));
    }

    function get16(Seed memory seed) internal pure returns (uint16) {
        return uint16(_get(seed, 2));
    }

    function get32(Seed memory seed) internal pure returns (uint32) {
        return uint32(_get(seed, 4));
    }

    function get64(Seed memory seed) internal pure returns (uint64) {
        return uint64(_get(seed, 8));
    }
}
