// SPDX-License-Identifier: Unlicense
/*
 * @title Solidity Bytes Arrays Utils
 * @author Gonçalo Sá <goncalo.sa@consensys.net>
 *
 * @dev Bytes tightly packed arrays utility library for ethereum contracts written in Solidity.
 *      The library lets you concatenate, slice and type cast bytes arrays both in memory and storage.
 */
pragma solidity >=0.8.0 <0.9.0;

library BytesLib {
    function concat(
        bytes memory _preBytes,
        bytes memory _postBytes
    ) internal pure returns (bytes memory) {
        bytes memory tempBytes;

        assembly {
            /**
             *@notice Get a location of some free memory and store it in tempBytes as
             *@notice Solidity does for memory variables.
             */
            tempBytes := mload(0x40)

            /**
             *@notice Store the length of the first bytes array at the beginning of
             *@notice the memory for tempBytes.
             */
            let length := mload(_preBytes)
            mstore(tempBytes, length)

            /**
             *@notice Maintain a memory counter for the current write location in the
             *@notice temp bytes array by adding the 32 bytes for the array length to
             *@notice the starting location.
             */
            let mc := add(tempBytes, 0x20)
            /**
             *@notice Stop copying when the memory counter reaches the length of the
             *@notice the memory for tempBytes.
             */
            let end := add(mc, length)

            for {
                /**
                 *@notice Initialize a copy counter to the start of the _preBytes data,
                 *@notice 32 bytes into its memory.
                 */
                let cc := add(_preBytes, 0x20)
            } lt(mc, end) {
                /**
                 *@notice Increase both counters by 32 bytes each iteration.
                 *@notice 32 bytes into its memory.
                 */
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                /**
                 *@notice Write the _preBytes data into the tempBytes memory 32 bytes
                 *@notice at a time.
                 */
                mstore(mc, mload(cc))
            }

            /**
             *@notice Add the length of _postBytes to the current length of tempBytes
             *@notice and store it as the new length in the first 32 bytes of the
             *@notice tempBytes memory.
             */
            length := mload(_postBytes)
            mstore(tempBytes, add(length, mload(tempBytes)))

            /**
             *@notice Move the memory counter back from a multiple of 0x20 to the
             *@notice actual end of the _preBytes data.
             */
            mc := end
            /**
             *@notice Stop copying when the memory counter reaches the new combined
             *@notice length of the arrays.
             */
            end := add(mc, length)

            for {
                let cc := add(_postBytes, 0x20)
            } lt(mc, end) {
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                mstore(mc, mload(cc))
            }

            /**
             *@notice Update the free-memory pointer by padding our last write location
             *@notice to 32 bytes: add 31 bytes to the end of tempBytes to move to the
             *@notice next 32 byte block, then round down to the nearest multiple of
             *@notice 32. If the sum of the length of the two arrays is zero then add
             *@notice one before rounding down to leave a blank 32 bytes (the length block with 0).
             */
            mstore(
                0x40,
                and(
                    add(add(end, iszero(add(length, mload(_preBytes)))), 31),
                    /**
                     *@notice Round down to the nearest 32 bytes.
                     */
                    not(31)
                )
            )
        }

        return tempBytes;
    }

    function concatStorage(
        bytes storage _preBytes,
        bytes memory _postBytes
    ) internal {
        assembly {
            /**
             *@notice Read the first 32 bytes of _preBytes storage, which is the length
             *@notice of the array. (We don't need to use the offset into the slot
             *@notice because arrays use the entire slot.)
             */
            let fslot := sload(_preBytes.slot)

            /**
             *@notice Arrays of 31 bytes or less have an even value in their slot,
             *@notice while longer arrays have an odd value. The actual length is
             *@notice the slot divided by two for odd values, and the lowest order
             *@notice byte divided by two for even values.
             *@notice If the slot is even, bitwise and the slot with 255 and divide by
             *@notice two to get the length. If the slot is odd, bitwise and the slot
             *@notice with -1 and divide by two.
             */
            let slength := div(
                and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)),
                2
            )
            let mlength := mload(_postBytes)
            let newlength := add(slength, mlength)
            /**
             *@notice slength can contain both the length and contents of the array
             *@notice if length < 32 bytes so let's prepare for that
             *@notice v. http://solidity.readthedocs.io/en/latest/miscellaneous.html#layout-of-state-variables-in-storage
             */
            switch add(lt(slength, 32), lt(newlength, 32))
            case 2 {
                /**
                 *@notice Since the new array still fits in the slot, we just need to
                 *@notice update the contents of the slot.
                 *@notice uint256(bytes_storage) = uint256(bytes_storage) + uint256(bytes_memory) + new_length
                 */
                sstore(
                    _preBytes.slot,
                    /**
                     *@notice all the modifications to the slot are inside this
                     *@notice next block
                     */
                    add(
                        /**
                         *@notice we can just add to the slot contents because the
                         *@notice bytes we want to change are the LSBs
                         */
                        fslot,
                        add(
                            mul(
                                div(
                                    /**
                                     *@notice  load the bytes from memory
                                     */
                                    mload(add(_postBytes, 0x20)),
                                    /**
                                     *@notice  zero all bytes to the right
                                     */
                                    exp(0x100, sub(32, mlength))
                                ),
                                /**
                                 *@notice  and now shift left the number of bytes to
                                 *@notice  leave space for the length in the slot
                                 */
                                exp(0x100, sub(32, newlength))
                            ),
                            /**
                             *@notice  increase length by the double of the memory
                             *@notice  bytes length
                             */
                            mul(mlength, 2)
                        )
                    )
                )
            }
            case 1 {
                /**
                 *@notice  The stored value fits in the slot, but the combined value
                 *@notice  will exceed it.
                 *@notice  get the keccak hash to get the contents of the array
                 */
                mstore(0x0, _preBytes.slot)
                let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                /**
                 *@notice   save new length
                 */
                sstore(_preBytes.slot, add(mul(newlength, 2), 1))
                /**
                 *@notice  The contents of the _postBytes array start 32 bytes into
                 *@notice  the structure. Our first read should obtain the `submod`
                 *@notice  bytes that can fit into the unused space in the last word
                 *@notice  of the stored array. To get this, we read 32 bytes starting
                 *@notice  from `submod`, so the data we read overlaps with the array
                 *@notice  contents by `submod` bytes. Masking the lowest-order
                 *@notice  contents by `submod` bytes. Masking the lowest-order
                 *@notice  stored value.
                 */
                let submod := sub(32, slength)
                let mc := add(_postBytes, submod)
                let end := add(_postBytes, mlength)
                let mask := sub(exp(0x100, submod), 1)

                sstore(
                    sc,
                    add(
                        and(
                            fslot,
                            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00
                        ),
                        and(mload(mc), mask)
                    )
                )

                for {
                    mc := add(mc, 0x20)
                    sc := add(sc, 1)
                } lt(mc, end) {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } {
                    sstore(sc, mload(mc))
                }

                mask := exp(0x100, sub(mc, end))

                sstore(sc, mul(div(mload(mc), mask), mask))
            }
            default {
                /**
                 *@notice get the keccak hash to get the contents of the array
                 */
                mstore(0x0, _preBytes.slot)

                /**
                 *@notice Start copying to the last used word of the stored array.
                 */
                let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                /**
                 *@notice save new length
                 */
                sstore(_preBytes.slot, add(mul(newlength, 2), 1))

                /**
                 *@notice Copy over the first `submod` bytes of the new data as in
                 *@notice case 1 above.
                 */
                let slengthmod := mod(slength, 32)
                let mlengthmod := mod(mlength, 32)
                let submod := sub(32, slengthmod)
                let mc := add(_postBytes, submod)
                let end := add(_postBytes, mlength)
                let mask := sub(exp(0x100, submod), 1)

                sstore(sc, add(sload(sc), and(mload(mc), mask)))

                for {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } lt(mc, end) {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } {
                    sstore(sc, mload(mc))
                }

                mask := exp(0x100, sub(mc, end))

                sstore(sc, mul(div(mload(mc), mask), mask))
            }
        }
    }

    /**
     *@notice to-do:check
     *@param _bytes  to-do:check
     *@param _start to-do:check
     *@param _length  to-do:check
     */
    function slice(
        bytes memory _bytes,
        uint256 _start,
        uint256 _length
    ) internal pure returns (bytes memory) {
        require(_length + 31 >= _length, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                /**
                 *@notice Get a location of some free memory and store it in tempBytes as
                 *@notice Solidity does for memory variables.
                 */
                tempBytes := mload(0x40)

                /**
                 *@notice The first word of the slice result is potentially a partial
                 *@notice word read from the original array. To read it, we calculate
                 *@notice the length of that partial word and start copying that many
                 *@notice bytes into the array. The first word we copy will start with
                 *@notice data we don't care about, but the last `lengthmod` bytes will
                 *@notice land at the beginning of the contents of the new array. When
                 *@notice we're done copying, we overwrite the full first word with
                 *@notice the actual length of the slice.
                 */
                let lengthmod := and(_length, 31)

                /**
                 *@notice The multiplication in the next line is necessary
                 *@notice because when slicing multiples of 32 bytes (lengthmod == 0)
                 *@notice the following copy loop was copying the origin's length
                 *@notice and then ending prematurely not copying everything it should.
                 */
                let mc := add(
                    add(tempBytes, lengthmod),
                    mul(0x20, iszero(lengthmod))
                )
                let end := add(mc, _length)

                for {
                    /**
                     *@notice The multiplication in the next line has the same exact purpose
                     *@notice as the one above.
                     */
                    let cc := add(
                        add(
                            add(_bytes, lengthmod),
                            mul(0x20, iszero(lengthmod))
                        ),
                        _start
                    )
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }

                mstore(tempBytes, _length)
                /**
                 *@notice update free-memory pointer
                 *@notice allocating the array padded to 32 bytes like the compiler does now
                 */
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            /**
             *@notice if we want a zero-length slice let's just return a zero-length array
             */
            default {
                tempBytes := mload(0x40)
                /**
                 *@notice zero out the 32 bytes slice we are about to return
                 *@notice we need to do it because Solidity does not garbage collect
                 */
                mstore(tempBytes, 0)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }

    function toAddress(
        bytes memory _bytes,
        uint256 _start
    ) internal pure returns (address) {
        require(_bytes.length >= _start + 20, "toAddress_outOfBounds");
        address tempAddress;

        assembly {
            tempAddress := div(
                mload(add(add(_bytes, 0x20), _start)),
                0x1000000000000000000000000
            )
        }

        return tempAddress;
    }

    function toUint8(
        bytes memory _bytes,
        uint256 _start
    ) internal pure returns (uint8) {
        require(_bytes.length >= _start + 1, "toUint8_outOfBounds");
        uint8 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }

        return tempUint;
    }

    function toUint16(
        bytes memory _bytes,
        uint256 _start
    ) internal pure returns (uint16) {
        require(_bytes.length >= _start + 2, "toUint16_outOfBounds");
        uint16 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x2), _start))
        }

        return tempUint;
    }

    function toUint24(
        bytes memory _bytes,
        uint256 _start
    ) internal pure returns (uint24) {
        require(_start + 3 >= _start, "toUint24_overflow");
        require(_bytes.length >= _start + 3, "toUint24_outOfBounds");
        uint24 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x3), _start))
        }

        return tempUint;
    }

    function toUint32(
        bytes memory _bytes,
        uint256 _start
    ) internal pure returns (uint32) {
        require(_bytes.length >= _start + 4, "toUint32_outOfBounds");
        uint32 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x4), _start))
        }

        return tempUint;
    }

    function toUint64(
        bytes memory _bytes,
        uint256 _start
    ) internal pure returns (uint64) {
        require(_bytes.length >= _start + 8, "toUint64_outOfBounds");
        uint64 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x8), _start))
        }

        return tempUint;
    }

    function toUint96(
        bytes memory _bytes,
        uint256 _start
    ) internal pure returns (uint96) {
        require(_bytes.length >= _start + 12, "toUint96_outOfBounds");
        uint96 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0xc), _start))
        }

        return tempUint;
    }

    function toUint128(
        bytes memory _bytes,
        uint256 _start
    ) internal pure returns (uint128) {
        require(_bytes.length >= _start + 16, "toUint128_outOfBounds");
        uint128 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x10), _start))
        }

        return tempUint;
    }

    function toUint256(
        bytes memory _bytes,
        uint256 _start
    ) internal pure returns (uint256) {
        require(_bytes.length >= _start + 32, "toUint256_outOfBounds");
        uint256 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }

    function toBytes32(
        bytes memory _bytes,
        uint256 _start
    ) internal pure returns (bytes32) {
        require(_bytes.length >= _start + 32, "toBytes32_outOfBounds");
        bytes32 tempBytes32;

        assembly {
            tempBytes32 := mload(add(add(_bytes, 0x20), _start))
        }

        return tempBytes32;
    }

    function equal(
        bytes memory _preBytes,
        bytes memory _postBytes
    ) internal pure returns (bool) {
        bool success = true;

        assembly {
            let length := mload(_preBytes)

            /**
             *@notice If lengths don't match the arrays are not equal
             */

            switch eq(length, mload(_postBytes))
            case 1 {
                /**
                 *@notice cb is a circuit breaker in the for loop since there's
                 *@notice no said feature for inline assembly loops
                 *@notice cb = 1 - don't breaker
                 *@notice cb = 0 - break
                 */
                let cb := 1

                let mc := add(_preBytes, 0x20)
                let end := add(mc, length)

                for {
                    let cc := add(_postBytes, 0x20)

                    /**
                     *@notice the next line is the loop condition:
                     *@notice while(uint256(mc < end) + cb == 2)
                     */
                } eq(add(lt(mc, end), cb), 2) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    /**
                     *@notice if any of these checks fails then arrays are not equal
                     */
                    if iszero(eq(mload(mc), mload(cc))) {
                        /**
                         *@notice unsuccess:
                         */
                        success := 0
                        cb := 0
                    }
                }
            }
            default {
                /**
                 *@notice unsuccess:
                 */
                success := 0
            }
        }

        return success;
    }

    function equalStorage(
        bytes storage _preBytes,
        bytes memory _postBytes
    ) internal view returns (bool) {
        bool success = true;

        assembly {
            /**
             *@notice we know _preBytes_offset is 0
             */
            let fslot := sload(_preBytes.slot)

            /**
             *@notice Decode the length of the stored array like in concatStorage().
             */
            let slength := div(
                and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)),
                2
            )
            let mlength := mload(_postBytes)

            /**
             *@notice if lengths don't match the arrays are not equal
             */
            switch eq(slength, mlength)
            case 1 {
                /**
                 *@notice slength can contain both the length and contents of the array
                 *@notice if length < 32 bytes so let's prepare for that
                 *@notice v. http://solidity.readthedocs.io/en/latest/miscellaneous.html#layout-of-state-variables-in-storage
                 */
                if iszero(iszero(slength)) {
                    switch lt(slength, 32)
                    case 1 {
                        /**
                         *@notice blank the last byte which is the length
                         */
                        fslot := mul(div(fslot, 0x100), 0x100)

                        if iszero(eq(fslot, mload(add(_postBytes, 0x20)))) {
                            /**
                             *@notice unsuccess:
                             */
                            success := 0
                        }
                    }
                    default {
                        /**
                         *@notice cb is a circuit breaker in the for loop since there's
                         *@notice no said feature for inline assembly loops
                         *@notice cb = 1 - don't breaker
                         *@notice cb = 0 - break
                         */
                        let cb := 1

                        /**
                         *@notice get the keccak hash to get the contents of the array
                         */
                        mstore(0x0, _preBytes.slot)
                        let sc := keccak256(0x0, 0x20)

                        let mc := add(_postBytes, 0x20)
                        let end := add(mc, mlength)

                        /**
                         *@notice the next line is the loop condition:
                         *@notice while(uint256(mc < end) + cb == 2)
                         */
                        for {

                        } eq(add(lt(mc, end), cb), 2) {
                            sc := add(sc, 1)
                            mc := add(mc, 0x20)
                        } {
                            if iszero(eq(sload(sc), mload(mc))) {
                                /**
                                 *@notice unsuccess:
                                 */
                                success := 0
                                cb := 0
                            }
                        }
                    }
                }
            }
            default {
                /**
                 *@notice unsuccess:
                 */
                success := 0
            }
        }

        return success;
    }
}

