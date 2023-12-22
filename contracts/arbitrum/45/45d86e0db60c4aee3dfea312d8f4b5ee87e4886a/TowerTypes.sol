//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

interface TowerTypes {
    struct TowerParams {
        bool isAntennasIncluded;
        uint maxHeight;
        uint heightInPixels;
        uint whiteBackgroundHeight;
        uint windowLength;
        uint fullWindowWidth;
        uint towerWidth;
        uint buildingStartingX;
        uint windowStartingX;
        uint8 roofHeight;
        uint8 numWindows;
        string colorForToken;
        string antennas;
        string windows;
    }
}
