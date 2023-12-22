// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface IContest {
    function acceptEntries(uint256[] memory entryIds) external;
    function setWinningEntry(uint256 entryId) external;
    function isClosed() external view returns (bool);
    function hasWinner() external view returns (bool);
    function getWinner() external view returns (address);
    function getWinningId() external view returns (uint256);
    function getEntrant(uint256 entryId) external view returns (address);
    function reclaimEntry(uint256 entryId) external;
    function getEntryURI(uint256 entryId) external returns (string memory);
}

