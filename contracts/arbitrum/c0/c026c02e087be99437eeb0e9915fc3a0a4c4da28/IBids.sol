// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBids {
    function draw(uint256 raffleId) external;

    function drawCallback(uint256 raffleId, uint256 randomNumber) external;

    function getCurrentRaffleId() external view returns (uint256);

    function isAvailableToDraw(uint256 raffleId) external view returns (bool);
}

