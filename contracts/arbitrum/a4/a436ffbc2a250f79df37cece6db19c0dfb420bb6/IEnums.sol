// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IEnums {
    enum LAUNCHPAD_TYPE {
        NORMAL,
        FAIR
    }

    enum LAUNCHPAD_STATE {
        OPENING,
        FINISHED,
        CANCELLED
    }
}

