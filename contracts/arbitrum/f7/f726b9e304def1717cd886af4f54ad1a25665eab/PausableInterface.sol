// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface PausableInterface {
    function isPaused() external view returns (bool);
}

