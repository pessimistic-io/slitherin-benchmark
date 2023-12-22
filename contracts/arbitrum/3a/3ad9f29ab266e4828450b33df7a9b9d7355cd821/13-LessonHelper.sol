// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract LessonThirteenHelper {
    int256 myValue = 100;

    function addTen(int256 number) public view returns (int256) {
        unchecked {
            return number + myValue + int256(10);
        }
    }
}

