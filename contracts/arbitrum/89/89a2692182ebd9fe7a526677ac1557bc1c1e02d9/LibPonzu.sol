// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./console.sol";

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";

import {PonzuStorage, PERCENTAGE_DENOMINATOR, RoundWinner, MAX_DEPOSIT, RoundParticipantData, RoundParticipantData, RoundSnapshot} from "./PonzuStorage.sol";
import {Participant} from "./Participant.sol";
import {IHamachi} from "./IHamachi.sol";
import {IBlackHole} from "./IBlackHole.sol";

import {AddressArrayLibUtils} from "./ArrayLibUtils.sol";

library LibPonzu {
  using LibPonzu for PonzuStorage;
  using SafeERC20 for IERC20;
  using AddressArrayLibUtils for address[];

  bytes32 internal constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.ponzu.storage");

  error DepositZeroAmount();
  error InsufficientDeposit();
  error MaxDepositReached();
  error NoDeposits();
  error RoundNotStarted(uint256 roundNumber);
  error RoundNotEnded(uint256 roundNumber);
  error WinnerNotFound(uint256 roundNumber);
  error NotCleaned();
  error AlreadyReceivedRandomNumber();
  error NoRandomNumber();

  event Deposit(address indexed participant, uint256 amount);
  event Withdraw(address indexed participant, uint256 amount);
  event WinnerSelected(address indexed winner, uint256 prize, uint256 roundNumber);
  event NoWinnerSelected(uint256 roundNumber);
  event RewardsAdded(uint256 amount);

  function DS() internal pure returns (PonzuStorage storage ds) {
    bytes32 position = DIAMOND_STORAGE_POSITION;
    assembly {
      ds.slot := position
    }
  }

  function addPausedTime(PonzuStorage storage ps, uint256 time) internal {
    ps.pausedTimeInRound += time;
  }

  function startRound(PonzuStorage storage ps, uint256 startTime) internal {
    uint256 lastClosedRound = ps.lastClosedRound;
    if (ps.startTime != 0) revert RoundNotEnded(lastClosedRound);
    ps.startTime = startTime;
  }

  function deposit(PonzuStorage storage ps, uint256 amount) internal {
    if (amount == 0) revert DepositZeroAmount();

    (uint256 currentRound, , uint256 curRoundDeadline, ) = ps.currentRoundTimes();

    uint256 lastClosedRound = ps.lastClosedRound;
    if (lastClosedRound + 1 == currentRound) {
      ps.participantDepositsCleanup(msg.sender, currentRound);

      Participant storage participant = ps.participants[msg.sender];

      uint256 initialTotal = participant.oldDepositAmount + participant.newDepositAmount;

      if (initialTotal == 0) ps.participantsList.push(msg.sender);
      if (block.timestamp > curRoundDeadline) {
        participant.newDepositAmount += amount;
        participant.newDepositRound = currentRound + 1;
      } else {
        participant.oldDepositAmount += amount;
      }

      ps.totalDeposited += amount;

      // update total deposited
      uint256 total = participant.oldDepositAmount + participant.newDepositAmount;
      if (total > MAX_DEPOSIT) revert MaxDepositReached();
      IERC20(ps.rewardToken).safeTransferFrom(msg.sender, address(this), amount);

      // update participant state
      emit Deposit(msg.sender, amount);
    } else revert RoundNotEnded(lastClosedRound);
  }

  function withdraw(PonzuStorage storage ps, uint256 amount) internal {
    Participant storage participant = ps.participants[msg.sender];

    uint256 participantBalance = participant.oldDepositAmount + participant.newDepositAmount;
    if (participantBalance < amount) revert InsufficientDeposit();
    // uint256 currentRound = ps.currentRoundNumber();
    // ps.participantDepositsCleanup(msg.sender, currentRound);

    // Update total deposited
    ps.totalDeposited -= amount;

    // remove from not yet valid deposits
    uint256 invalidAmount = participant.newDepositAmount;
    if (invalidAmount >= amount) participant.newDepositAmount -= amount;
    else {
      participant.newDepositAmount = 0;
      uint256 amountLeft = amount - invalidAmount;

      // remove from valid deposits
      uint256 oldDepositAmount = participant.oldDepositAmount;
      participant.oldDepositAmount = oldDepositAmount - amountLeft;
      if (oldDepositAmount == 0) ps.participantsList.swapOut(msg.sender);
    }

    // Transfer tokens to participant
    IERC20(DS().rewardToken).transfer(msg.sender, amount);
    emit Withdraw(msg.sender, amount);
  }

  function currentRoundNumber(PonzuStorage storage ps) internal view returns (uint256) {
    return ps.lastClosedRound + 1;
  }

  function currentRoundStartTime(PonzuStorage storage ps) internal view returns (uint256) {
    return ps.startTime;
  }

  function currentRoundDeadline(PonzuStorage storage ps) internal view returns (uint256) {
    return ps.startTime + ps.pausedTimeInRound + ps.depositDeadline;
  }

  function currentRoundEndTime(PonzuStorage storage ps) internal view returns (uint256) {
    return ps.startTime + ps.pausedTimeInRound + ps.roundDuration;
  }

  function currentRoundTimes(
    PonzuStorage storage ps
  )
    internal
    view
    returns (
      uint256 currentRound,
      uint256 curRoundStartTime,
      uint256 curRoundDeadline,
      uint256 curRoundEndTime
    )
  {
    currentRound = ps.currentRoundNumber();
    curRoundStartTime = ps.startTime;
    curRoundDeadline = ps.startTime + ps.pausedTimeInRound + ps.depositDeadline;
    curRoundEndTime = ps.currentRoundEndTime();
  }

  function sumTotalValidDeposits(PonzuStorage storage ps) internal view returns (uint256 total) {
    for (uint256 i = 0; i < ps.participantsList.length; i++) {
      total += ps.participants[ps.participantsList[i]].oldDepositAmount;
      if (ps.participants[ps.participantsList[i]].newDepositRound < ps.currentRoundNumber())
        total += ps.participants[ps.participantsList[i]].newDepositAmount;
    }
  }

  function participantValidDeposits(
    PonzuStorage storage ps,
    address user
  ) internal view returns (uint256 total) {
    Participant memory participant = ps.participants[user];
    total = participant.oldDepositAmount;
    if (participant.newDepositRound < ps.currentRoundNumber())
      total += participant.newDepositAmount;
  }

  function participantTotalDeposits(
    PonzuStorage storage ps,
    address user
  ) internal view returns (uint256 total) {
    Participant memory participant = ps.participants[user];
    total = participant.oldDepositAmount + participant.newDepositAmount;
  }

  function participantPendingDeposits(
    PonzuStorage storage ps,
    address user
  ) internal view returns (uint256 total) {
    Participant memory participant = ps.participants[user];
    if (participant.newDepositRound > ps.currentRoundNumber()) total = participant.newDepositAmount;
  }

  function participantDeposits(
    PonzuStorage storage ps,
    address user
  ) internal view returns (uint256 valid, uint256 pending) {
    Participant memory participant = ps.participants[user];
    valid = participant.oldDepositAmount;
    if (participant.newDepositRound > ps.currentRoundNumber())
      pending = participant.newDepositAmount;
    else valid += participant.newDepositAmount;
  }

  function checkIfNeedCleanup(
    PonzuStorage storage ps,
    address _participantAddress,
    uint256 roundNumber
  ) internal view returns (bool) {
    Participant memory participant = ps.participants[_participantAddress];
    return checkIfNeedCleanup(participant, roundNumber);
  }

  function checkIfNeedCleanup(
    Participant memory participant,
    uint256 roundNumber
  ) internal pure returns (bool) {
    return participant.newDepositRound <= roundNumber && participant.newDepositAmount > 0;
  }

  function participantDepositsCleanup(
    PonzuStorage storage ps,
    address _participantAddress,
    uint256 roundNumber
  ) internal {
    if (!ps.checkIfNeedCleanup(_participantAddress, roundNumber)) return;
    Participant storage participant = ps.participants[_participantAddress];
    participant.oldDepositAmount += participant.newDepositAmount;
    participant.newDepositAmount = 0;
  }

  function receiveRandomNumber(PonzuStorage storage ps, uint256 randomNum) internal {
    if (!ps.receivedRandomNumber) {
      ps.receivedRandomNumber = true;
      ps.randomNumber = randomNum;
    } else revert AlreadyReceivedRandomNumber();
  }

  function selectWinner(PonzuStorage storage ps, uint256 randomNumIn, bool manual) internal {
    uint256 randomNum = uint256(keccak256(abi.encodePacked(randomNumIn)));
    (uint256 roundNum, , uint256 roundDeadline, ) = ps.currentRoundTimes();
    if (block.timestamp < roundDeadline) revert RoundNotEnded(roundNum);

    // claim rewards which will serve as the prize
    ps.claimRewards();
    uint256 prizeAmount = ps.currentStoredRewards;
    uint256 blackHoleAmount = (prizeAmount * ps.blackHoleShare) / PERCENTAGE_DENOMINATOR;
    uint256 winnerAmount = prizeAmount - blackHoleAmount;
    address winnerAddress = manual
      ? ps._selectWinnerManual(roundNum, randomNum)
      : ps._selectWinner(roundNum, address(this), randomNum);

    if (winnerAddress == address(0)) revert WinnerNotFound(randomNum);
    ps.roundWinners[roundNum] = RoundWinner(winnerAddress, winnerAmount, randomNum);

    // feed part of prize to blackhole
    if (blackHoleAmount > 0) {
      IERC20(ps.rewardToken).transfer(ps.blackHole, blackHoleAmount);
      IBlackHole(ps.blackHole).feedBlackHole();
    }

    // reset rewards to 0
    ps.currentStoredRewards = 0;

    // if maxDeposit is reached transfer to winner
    if (
      winnerAmount > 0 &&
      IERC20(ps.rewardToken).balanceOf(winnerAddress) + winnerAmount > MAX_DEPOSIT
    ) {
      IERC20(ps.rewardToken).transfer(winnerAddress, winnerAmount);
    } else {
      ps.participants[winnerAddress].oldDepositAmount += winnerAmount;
    }

    emit WinnerSelected(winnerAddress, winnerAmount, roundNum);

    // update last closed round
    ps.lastClosedRound = roundNum;
    ps.startTime = 0;
    ps.pausedTimeInRound = 0;
    ps.receivedRandomNumber = false;
    ps.isCleaned = false;
    ps.cleanupIndex = 0;
  }

  function _selectWinner(
    PonzuStorage storage ps,
    uint256 roundNum,
    address diamondAddress,
    uint256 randomNum
  ) internal view returns (address winnerAddress) {
    RoundSnapshot memory roundSnapshot = ps.roundSnapshot[roundNum];
    uint256 totalParticipantsCount = roundSnapshot.totalParticipantsCount;
    // divide number by total deposited
    uint256 winnerNumber = randomNum % roundSnapshot.totalDeposited;

    // binary search for when totalParticipantsCount is too large
    uint256 winnerIndex = ps.binarySearch(roundNum, diamondAddress, winnerNumber);
    RoundParticipantData memory winnerData = ps.getRoundParticipantData(
      roundNum,
      diamondAddress,
      winnerIndex
    );
    return winnerData.participantAddress;
  }

  function _selectWinnerManual(
    PonzuStorage storage ps,
    uint256 roundNum,
    uint256 randomNum
  ) internal returns (address winnerAddress) {
    // divide number by total deposited
    uint256 winnerNumber = randomNum % ps.sumTotalValidDeposits();

    // iterate over participants to find winner
    for (uint256 i = 0; i < ps.participantsList.length; ++i) {
      ps.participantDepositsCleanup(ps.participantsList[i], roundNum);
      address participant = ps.participantsList[i];
      uint256 pDeposit = ps.participants[participant].oldDepositAmount;
      if (pDeposit >= winnerNumber) {
        winnerAddress = participant;
        break;
      } else {
        winnerNumber -= pDeposit;
      }
    }
  }

  // efficient binary search for when totalParticipantsCount is too large
  function binarySearch(
    PonzuStorage storage ps,
    uint256 roundNum,
    address diamondAddress,
    uint256 targetNum
  ) internal view returns (uint256 left) {
    RoundSnapshot memory roundSnapshot = ps.roundSnapshot[roundNum];
    uint256 right = roundSnapshot.totalParticipantsCount;
    while (right - left > 1) {
      uint256 mid = (left + right) / 2;
      RoundParticipantData memory midData = ps.getRoundParticipantData(
        roundNum,
        diamondAddress,
        mid
      );
      uint256 midValue = midData.participantNumber;
      if (midValue <= targetNum) left = mid;
      else right = mid;
    }
  }

  // returns -1 if finished, otherwise returns the index of the next participant to cleanup
  function cleanupAllParticipants(PonzuStorage storage ps, uint256 roundNum) internal {
    uint256 endIndex = ps.participantsList.length;
    for (uint256 i = 0; i < endIndex; i++) {
      address participantAddr = ps.participantsList[i];
      ps.participantDepositsCleanup(participantAddr, roundNum);
    }
  }

  // returns -1 if finished, otherwise returns the index of the next participant to cleanup
  function cleanupAllParticipantsContinued(
    PonzuStorage storage ps,
    uint256 roundNum,
    bool restartCleanup
  ) internal returns (int256) {
    uint256 index = 0;
    uint256 totalDeposited = 0;
    uint256 totalParticipantsCount = 0;
    if (!restartCleanup) {
      index = ps.cleanupIndex;

      RoundSnapshot memory roundSnapshot = ps.roundSnapshot[roundNum];
      totalParticipantsCount = roundSnapshot.totalParticipantsCount;
      totalDeposited = roundSnapshot.totalDeposited;
    }
    uint256 endIndex = ps.participantsList.length;

    while (index < endIndex) {
      if (gasleft() < 100000) {
        ps.cleanupIndex = index;
        ps.roundSnapshot[roundNum] = RoundSnapshot(totalParticipantsCount, totalDeposited);
        return int256(index);
      }
      address participantAddr = ps.participantsList[index];
      ps.participantDepositsCleanup(participantAddr, roundNum);

      if (ps.participants[participantAddr].oldDepositAmount != 0) {
        totalDeposited += ps.participants[participantAddr].oldDepositAmount;
        bytes32 participantKey = getRoundParticipantKey(
          roundNum,
          address(this),
          totalParticipantsCount
        );
        ps.roundParticipants[participantKey] = RoundParticipantData(
          participantAddr,
          totalDeposited
        );
        totalParticipantsCount++;
      }

      index++;
    }
    ps.roundSnapshot[roundNum] = RoundSnapshot(totalParticipantsCount, totalDeposited);
    ps.cleanupIndex = index;
    ps.isCleaned = true;
    return -1;
  }

  function cleanupAllParticipantsByIndex(
    PonzuStorage storage ps,
    uint256 roundNum,
    uint256 startIndex,
    uint256 endIndex
  ) internal {
    for (uint256 i = startIndex; i < endIndex; ++i) {
      ps.participantDepositsCleanup(ps.participantsList[i], roundNum);
    }
  }

  function endRoundWithoutWinner(PonzuStorage storage ps) internal {
    (uint256 roundNum, , uint256 roundDeadline, ) = ps.currentRoundTimes();
    if (block.timestamp < roundDeadline) revert RoundNotEnded(roundNum);

    uint256 lastRound = ps.lastClosedRound;

    // update last closed round
    ps.lastClosedRound = lastRound + 1;
    ps.startTime = 0;
    ps.pausedTimeInRound = 0;
    emit NoWinnerSelected(lastRound);
  }

  function currentPrizePool(
    PonzuStorage storage ps
  ) internal view returns (uint256 withdrawableRewards) {
    (, , , , withdrawableRewards, , ) = IHamachi(ps.rewardToken).getRewardAccount(address(this));
    withdrawableRewards += ps.currentStoredRewards;
  }

  function addRewards(PonzuStorage storage ps, address giver, uint256 amount) internal {
    IERC20(ps.rewardToken).safeTransferFrom(giver, address(this), amount);
    ps.currentStoredRewards += amount;
    emit RewardsAdded(amount);
  }

  function claimRewards(PonzuStorage storage ps) internal returns (uint256) {
    uint256 initialRewardTokenBalance = IERC20(ps.rewardToken).balanceOf(address(this));
    IHamachi(ps.rewardToken).claimRewards(true, 0);
    uint256 prizeAmount = IERC20(ps.rewardToken).balanceOf(address(this)) -
      initialRewardTokenBalance;

    if (prizeAmount > 0) {
      ps.currentStoredRewards += prizeAmount;
      emit RewardsAdded(prizeAmount);
    }

    return prizeAmount;
  }

  function getPausedTimeInRound(PonzuStorage storage ps) internal view returns (uint256) {
    if (ps.pausedTimeInRound == 0) return 0;
    return ps.pausedTimeInRound;
  }

  function getRoundParticipantKey(
    uint256 roundNum,
    address diamond,
    uint256 participantIndex
  ) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(roundNum, diamond, participantIndex));
  }

  function getRoundParticipantData(
    PonzuStorage storage ps,
    uint256 roundNum,
    address diamond,
    uint256 participantIndex
  ) internal view returns (RoundParticipantData memory) {
    bytes32 participantKey = getRoundParticipantKey(roundNum, diamond, participantIndex);
    return ps.roundParticipants[participantKey];
  }
}

