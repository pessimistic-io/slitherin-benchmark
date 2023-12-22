// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IGlpManager {
    function getAum(bool) external view returns (uint256);
    function getAumInUsdg(bool maximise) external view returns (uint256);
}
