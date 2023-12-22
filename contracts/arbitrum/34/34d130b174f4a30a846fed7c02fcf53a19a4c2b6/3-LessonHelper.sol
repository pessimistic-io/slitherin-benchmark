// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

contract LessonThreeHelper {
    bool[5] internal s_booleanArray;

    function getArrayElement(uint256 index) external view returns (bool) {
        return s_booleanArray[index];
    }
}

