// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface IGlpManager {
    function getAum(bool maximise) external view returns (uint256);
}


