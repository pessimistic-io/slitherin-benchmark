// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

/**
 * @dev Library for managing uint8 to bool mapping in a compact and efficient way, providing the keys are sequential.
 * Interface modified from OpenZeppelin's https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/structs/BitMaps.sol.
 */
library UintBitMap {
    /**
     * @dev Returns whether the bit at `index` is set.
     */
    function get(uint256 bitmap, uint8 index) internal pure returns (bool) {
        return (bitmap >> index) & 1 != 0;
    }

    /**
     * @dev Sets the bit at `index` to the boolean `value`.
     */
    // slither-disable-next-line dead-code
    function setTo(
        uint256 bitmap,
        uint8 index,
        bool value
    ) internal pure returns (uint256) {
        if (value) {
            return set(bitmap, index);
        } else {
            return unset(bitmap, index);
        }
    }

    /**
     * @dev Sets the bit at `index`.
     */
    function set(uint256 bitmap, uint8 index) internal pure returns (uint256) {
        return bitmap | uint256(1 << index);
    }

    /**
     * @dev Unsets the bit at `index`.
     */
    // slither-disable-next-line dead-code
    function unset(uint256 bitmap, uint8 index) internal pure returns (uint256) {
        return bitmap & ~uint256(1 << index);
    }
}

