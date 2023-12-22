// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IGlpManager {
    function getAum(bool _maximize) external view returns (uint256);
}

