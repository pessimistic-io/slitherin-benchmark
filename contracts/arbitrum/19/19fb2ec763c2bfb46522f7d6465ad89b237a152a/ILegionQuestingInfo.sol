// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILegionQuestingInfo {
    function requestIdForLegion(uint256 _legionId) external view returns(uint256);
    function additionalCorruptedCellsForLegion(uint256 _legionId) external view returns(uint8);
}
