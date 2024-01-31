// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

import "./FiguresDoubleDigitsLib.sol";
import "./FiguresUtilLib.sol";

library FiguresDoubles {
    function chooseStringsDoubles(
        uint8 number,
        uint8 index1,
        uint8 index2
    ) public pure returns (bool[][2] memory b) {
        FiguresUtilLib.FigStrings memory strings = getFigStringsDoubles(number);
        return
            FiguresUtilLib._chooseStringsDouble(
                number,
                strings.s1,
                strings.s2,
                index1,
                index2
            );
    }

    function getFigStringsDoubles(uint8 number)
        private
        pure
        returns (FiguresUtilLib.FigStrings memory)
    {
        FiguresUtilLib.FigStrings memory figStrings;

        do {
            if (number == 0) {
                figStrings.s1 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS0S1,
                    8
                );
                figStrings.s2 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS0S2,
                    8
                );
                break;
            }
            if (number == 1) {
                figStrings.s1 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS1S1,
                    24
                );
                figStrings.s2 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS1S2,
                    24
                );
                break;
            }
            if (number == 2) {
                figStrings.s1 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS2S1,
                    24
                );
                figStrings.s2 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS2S2,
                    24
                );
                break;
            }
            if (number == 3) {
                figStrings.s1 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS3S1,
                    24
                );
                figStrings.s2 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS3S2,
                    24
                );
                break;
            }
            if (number == 4) {
                figStrings.s1 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS4S1,
                    9
                );
                figStrings.s2 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS4S2,
                    16
                );
                break;
            }
            if (number == 5) {
                figStrings.s1 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS5S1,
                    24
                );
                figStrings.s2 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS5S2,
                    24
                );
                break;
            }
            if (number == 6) {
                figStrings.s1 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS6S1,
                    24
                );
                figStrings.s2 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS6S2,
                    33
                );
                break;
            }
            if (number == 7) {
                figStrings.s1 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS7S1,
                    13
                );
                figStrings.s2 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS7S2,
                    4
                );
                break;
            }
            if (number == 8) {
                figStrings.s1 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS8S1,
                    36
                );
                figStrings.s2 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS8S2,
                    36
                );
                break;
            }
            if (number == 9) {
                figStrings.s1 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS9S1,
                    36
                );
                figStrings.s2 = FiguresUtilLib._assignValuesDouble(
                    FiguresDoubleDigitsLib.FS9S2,
                    24
                );
                break;
            }
        } while (false);

        return figStrings;
    }
}

