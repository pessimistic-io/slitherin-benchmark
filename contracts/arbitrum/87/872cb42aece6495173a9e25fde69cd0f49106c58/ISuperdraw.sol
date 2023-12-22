// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISuperdraw {
    function addTickets(uint256 numTickets, address entrant, uint256 amountAddedToPrizePool) external;
}
