// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Participant} from "./Participant.sol";

struct PonzuStorage {
  address rewardToken;
  address blackHole;
  uint256 blackHoleShare;
  mapping(address => Participant) participants; // deprecating
  address[] participantsList;
  uint256 startTime;
  uint256 pausedTimeInRound;
  uint256 totalDeposited;
  uint256 lastClosedRound;
  mapping(uint256 => RoundWinner) roundWinners;
  uint256 currentStoredRewards;
  uint256 cleanupIndex; // deprecating
  uint256 roundDuration;
  uint256 depositDeadline;
  bool isCleaned; // deprecating
  bool receivedRandomNumber;
  uint256 randomNumber;
  mapping(uint256 => RoundSnapshot) roundSnapshot; // deprecating
  mapping(bytes32 => RoundParticipantData) roundParticipants; // deprecating
  mapping(address => ParticipantDeposit) participantDeposits;
}

struct RoundWinner {
  address winner;
  uint256 prize;
  uint256 randomNumber;
}

struct RoundSnapshot {
  uint256 totalParticipantsCount;
  uint256 totalDeposited;
}
struct RoundParticipantData {
  address participantAddress;
  uint256 participantNumber;
}

struct ParticipantDeposit {
  uint256 timestamp;
  uint256 amount;
}

uint256 constant MAX_DEPOSIT = 5 * 10 ** 24; // 5M tokens
uint256 constant PERCENTAGE_DENOMINATOR = 10000;

