// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

/// @title Uint48 length 5 array functions
/// @dev Fits in one storage slot
library Uint48L5ArrayLib {
    using Uint48L5ArrayLib for uint48[5];

    uint8 constant LENGTH = 5;

    error U48L5_IllegalElement(uint48 element);
    error U48L5_NoSpaceLeftToInsert(uint48 element);

    /// @notice Inserts an element in the array
    /// @dev Replaces a zero value in the array with element
    /// @param array Array to modify
    /// @param element Element to insert
    function include(uint48[5] storage array, uint48 element) internal {
        if (element == 0) {
            revert U48L5_IllegalElement(0);
        }

        uint256 emptyIndex = LENGTH; // LENGTH is an invalid index
        for (uint256 i; i < LENGTH; i++) {
            if (array[i] == element) {
                // if element already exists in the array, do nothing
                return;
            }
            // if we found an empty slot, remember it
            if (array[i] == uint48(0)) {
                emptyIndex = i;
                break;
            }
        }

        // if empty index is still LENGTH, there is no space left to insert
        if (emptyIndex == LENGTH) {
            revert U48L5_NoSpaceLeftToInsert(element);
        }

        array[emptyIndex] = element;
    }

    /// @notice Excludes the element from the array
    /// @dev If element exists, it swaps with last element and makes last element zero
    /// @param array Array to modify
    /// @param element Element to remove
    function exclude(uint48[5] storage array, uint48 element) internal {
        if (element == 0) {
            revert U48L5_IllegalElement(0);
        }

        uint256 elementIndex = LENGTH; // LENGTH is an invalid index
        uint256 i;

        for (; i < LENGTH; i++) {
            if (array[i] == element) {
                // element index in the array
                elementIndex = i;
            }
            if (array[i] == 0) {
                // last non-zero element
                i = i > 0 ? i - 1 : 0;
                break;
            }
        }

        // if array is full, i == LENGTH
        // hence swapping with element at last index
        i = i == LENGTH ? LENGTH - 1 : i;

        if (elementIndex != LENGTH) {
            if (i == elementIndex) {
                // if element is last element, simply make it zero
                array[elementIndex] = 0;
            } else {
                // move last to element's place and empty lastIndex slot
                (array[elementIndex], array[i]) = (array[i], 0);
            }
        }
    }

    /// @notice Returns the index of the element in the array
    /// @param array Array to perform search on
    /// @param element Element to search
    /// @return index if exists or LENGTH otherwise
    function indexOf(uint48[5] storage array, uint48 element) internal view returns (uint8) {
        for (uint8 i; i < LENGTH; i++) {
            if (array[i] == element) {
                return i;
            }
        }
        return LENGTH; // LENGTH is an invalid index
    }

    /// @notice Checks whether the element exists in the array
    /// @param array Array to perform search on
    /// @param element Element to search
    /// @return True if element is found, false otherwise
    function exists(uint48[5] storage array, uint48 element) internal view returns (bool) {
        return array.indexOf(element) != LENGTH; // LENGTH is an invalid index
    }

    /// @notice Returns length of array (number of non-zero elements)
    /// @param array Array to perform search on
    /// @return Length of array
    function numberOfNonZeroElements(uint48[5] storage array) internal view returns (uint256) {
        for (uint8 i; i < LENGTH; i++) {
            if (array[i] == 0) {
                return i;
            }
        }
        return LENGTH;
    }

    /// @notice Checks whether the array is empty or not
    /// @param array Array to perform search on
    /// @return True if the set does not have any token position active
    function isEmpty(uint48[5] storage array) internal view returns (bool) {
        return array[0] == 0;
    }
}

