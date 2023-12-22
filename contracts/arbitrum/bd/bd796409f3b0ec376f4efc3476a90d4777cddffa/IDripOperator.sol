// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDripOperator {
    // returns true if a report was finished
    function drip(uint256 fundId, uint256 tradeTvl) external returns (bool);
    function isDripInProgress(uint256 fundId) external view returns (bool);
    function isDripEnabled(uint256 fundId) external view returns (bool);
}
