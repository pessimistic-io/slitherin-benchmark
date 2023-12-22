// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface PausableInterfaceV5{
    function isPaused() external view returns (bool);
}
