// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRandomNumbers {
    function getRandomNumber(uint256 drawIndex) external;
    function fulfillRandomness(bytes32 requestId, uint256 randomness) external;
}
