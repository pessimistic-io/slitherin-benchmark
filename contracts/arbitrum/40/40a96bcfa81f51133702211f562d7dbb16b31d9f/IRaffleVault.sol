// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

interface IRaffleVault {
  struct Depositor {
    uint256 averageDeposits;
    uint256 totalDeposits;
    uint256 numberOfDeposits;
    uint256 bonus;
    uint256 lastDepositTime;
  }

  struct Raffle {
    uint256 timestamp;
    uint256 totalTWAB;
    address winner;
    uint256 amount0;
    uint256 amount1;
    uint256 numberOfParticipants;
  }

  event RaffleDeposit(uint256 indexed raffleId, Raffle raffle, address depositor, uint256 amount, uint256 avg, uint256 bonus);
  event RaffleWithdraw(uint256 indexed raffleId, Raffle raffle, address depositor);
  event RaffleClosed(uint256 indexed raffleId, Raffle raffle, address[] depositors);

  function closeRaffle() external;
}

