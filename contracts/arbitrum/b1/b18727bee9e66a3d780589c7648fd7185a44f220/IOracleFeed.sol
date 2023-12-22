// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IOracleFeed {
    function getLatestAnswer() external view returns (uint);
    function getLatestAnswerTime() external view returns (uint);
}
