// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

import "./Figure0DigitLib.sol";
import "./Figure1DigitLib.sol";
import "./Figure2DigitLib.sol";
import "./Figure3DigitLib.sol";
import "./Figure4DigitLib.sol";
import "./Figure5DigitLib.sol";
import "./Figure6DigitLib.sol";
import "./Figure7DigitLib.sol";
import "./Figure8DigitLib.sol";
import "./Figure9DigitLib.sol";
import "./FiguresUtilLib.sol";

library FiguresSingles {
    function chooseStringsSingles(
        uint8 number,
        uint8 index1,
        uint8 index2
    ) public pure returns (bool[][2] memory b) {
        FiguresUtilLib.FigStrings memory strings = getFigStringsSingles(number);
        return
            FiguresUtilLib._chooseStringsSingle(
                number,
                strings.s1,
                strings.s2,
                index1,
                index2
            );
    }

    function getFigStringsSingles(uint8 number)
        private
        pure
        returns (FiguresUtilLib.FigStrings memory)
    {
        FiguresUtilLib.FigStrings memory figStrings;

        do {
            if (number == 0) {
                figStrings.s1 = FiguresUtilLib._assignValuesSingle(
                    Figure0DigitLib.S1(),
                    144
                );
                figStrings.s2 = FiguresUtilLib._assignValuesSingle(
                    Figure0DigitLib.S2(),
                    144
                );
                break;
            }
            if (number == 1) {
                figStrings.s1 = FiguresUtilLib._assignValuesSingle(
                    Figure1DigitLib.S1(),
                    28
                );
                figStrings.s2 = FiguresUtilLib._assignValuesSingle(
                    Figure1DigitLib.S2(),
                    28
                );
                break;
            }
            if (number == 2) {
                figStrings.s1 = FiguresUtilLib._assignValuesSingle(
                    Figure2DigitLib.S1(),
                    54
                );
                figStrings.s2 = FiguresUtilLib._assignValuesSingle(
                    Figure2DigitLib.S2(),
                    54
                );
                break;
            }
            if (number == 3) {
                figStrings.s1 = FiguresUtilLib._assignValuesSingle(
                    Figure3DigitLib.S1(),
                    54
                );
                figStrings.s2 = FiguresUtilLib._assignValuesSingle(
                    Figure3DigitLib.S2(),
                    54
                );
                break;
            }
            if (number == 4) {
                figStrings.s1 = FiguresUtilLib._assignValuesSingle(
                    Figure4DigitLib.S1(),
                    108
                );
                figStrings.s2 = FiguresUtilLib._assignValuesSingle(
                    Figure4DigitLib.S2(),
                    30
                );
                break;
            }
            if (number == 5) {
                figStrings.s1 = FiguresUtilLib._assignValuesSingle(
                    Figure5DigitLib.S1(),
                    54
                );
                figStrings.s2 = FiguresUtilLib._assignValuesSingle(
                    Figure5DigitLib.S2(),
                    54
                );
                break;
            }
            if (number == 6) {
                figStrings.s1 = FiguresUtilLib._assignValuesSingle(
                    Figure6DigitLib.S1(),
                    54
                );
                figStrings.s2 = FiguresUtilLib._assignValuesSingle(
                    Figure6DigitLib.S2(),
                    216
                );
                break;
            }
            if (number == 7) {
                figStrings.s1 = FiguresUtilLib._assignValuesSingle(
                    Figure7DigitLib.S1(),
                    18
                );
                figStrings.s2 = FiguresUtilLib._assignValuesSingle(
                    Figure7DigitLib.S2(),
                    6
                );
                break;
            }
            if (number == 8) {
                figStrings.s1 = FiguresUtilLib._assignValuesSingle(
                    Figure8DigitLib.S1(),
                    216
                );
                figStrings.s2 = FiguresUtilLib._assignValuesSingle(
                    Figure8DigitLib.S2(),
                    216
                );
                break;
            }
            if (number == 9) {
                figStrings.s1 = FiguresUtilLib._assignValuesSingle(
                    Figure9DigitLib.S1(),
                    216
                );
                figStrings.s2 = FiguresUtilLib._assignValuesSingle(
                    Figure9DigitLib.S2(),
                    54
                );
                break;
            }
        } while (false);

        return figStrings;
    }
}

