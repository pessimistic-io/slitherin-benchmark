// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface LessonNine {
    error LessonNine__WrongValue();

    /*
     * CALL THIS FUNCTION!
     *
     * @param randomGuess - Your random guess... or not so random
     * @param yourTwitterHandle - Your twitter handle. Can be a blank string.
     */
    function solveChallenge(
        uint256 randomGuess,
        string memory yourTwitterHandle
    ) external;
}

