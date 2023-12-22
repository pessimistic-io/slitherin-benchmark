// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./console.sol";

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";

import {PonzuStorage, PERCENTAGE_DENOMINATOR, RoundWinner, MAX_DEPOSIT, ParticipantDeposit} from "./PonzuStorage.sol";
import {IHamachi} from "./IHamachi.sol";
import {IBlackHole} from "./IBlackHole.sol";

import {AddressArrayLibUtils} from "./ArrayLibUtils.sol";

library LibPonzu {
  using LibPonzu for PonzuStorage;
  using SafeERC20 for IERC20;
  using AddressArrayLibUtils for address[];

  bytes32 internal constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.ponzu.storage"); // has to be exactly the same as in V1

  error DepositZeroAmount();
  error WithdrawZeroAmount();
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

  function deposit(PonzuStorage storage ps, address user, uint256 amount) internal {
    if (amount == 0) revert DepositZeroAmount();

    ParticipantDeposit storage participantDeposit = ps.participantDeposits[user];
    uint256 total = participantDeposit.amount + amount;
    if (total > MAX_DEPOSIT) revert MaxDepositReached();

    participantDeposit.amount = total;

    if (participantDeposit.timestamp == 0) {
      // has no deposits yet
      participantDeposit.timestamp = block.timestamp;
      // add to participants list
      ps.participantsList.push(user);
    }
    
    // update total deposited
    ps.totalDeposited += amount;
    IERC20(ps.rewardToken).safeTransferFrom(user, address(this), amount);

    // emit event
    emit Deposit(user, amount);
  }

  function withdraw(PonzuStorage storage ps, address user, uint256 amount) internal {
    if (amount == 0) revert WithdrawZeroAmount();
    ParticipantDeposit storage participantDeposit = ps.participantDeposits[user];

    uint256 participantBalance = participantDeposit.amount;
    if (participantBalance < amount) revert InsufficientDeposit();

    // remove from participant deposits
    uint256 newBalance = participantBalance - amount;
    participantDeposit.amount = newBalance;
    if (newBalance == 0) {
      participantDeposit.timestamp = 0;
      ps.participantsList.swapOut(user);
    }

    // Update total deposited
    ps.totalDeposited -= amount;

    // Transfer tokens to participant
    IERC20(DS().rewardToken).transfer(user, amount);

    // emit event
    emit Withdraw(user, amount);
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

  function receiveRandomNumber(PonzuStorage storage ps, uint256 randomNum) internal {
    if (!ps.receivedRandomNumber) {
      ps.receivedRandomNumber = true;
      ps.randomNumber = randomNum;
    } else revert AlreadyReceivedRandomNumber();
  }

  function selectWinner(PonzuStorage storage ps, uint256 randomNumIn) internal {
    uint256 randomNum = uint256(keccak256(abi.encodePacked(randomNumIn)));
    (uint256 roundNum, , uint256 roundDeadline, ) = ps.currentRoundTimes();
    if (block.timestamp < roundDeadline) revert RoundNotEnded(roundNum);

    // claim rewards which will serve as the prize
    ps.claimRewards();
    uint256 prizeAmount = ps.currentStoredRewards;
    uint256 blackHoleAmount = (prizeAmount * ps.blackHoleShare) / PERCENTAGE_DENOMINATOR;
    uint256 winnerAmount = prizeAmount - blackHoleAmount;
    address winnerAddress = ps._selectWinner(randomNum, roundDeadline);

    if (winnerAddress == address(0)) revert WinnerNotFound(randomNum);
    ps.roundWinners[roundNum] = RoundWinner(winnerAddress, winnerAmount, randomNum);

    // feed part of prize to blackhole
    if (blackHoleAmount > 0) {
      IERC20(ps.rewardToken).transfer(ps.blackHole, blackHoleAmount);
      IBlackHole(ps.blackHole).feedBlackHole();
    }

    // reset rewards to 0
    ps.currentStoredRewards = 0;

    uint256 winnerTotalDeposit = ps.participantDeposits[winnerAddress].amount;

    // if maxDeposit is reached transfer to winner
    uint256 newWinnerTotalDeposit = winnerTotalDeposit + winnerAmount;
    if (winnerAmount > 0 && newWinnerTotalDeposit > MAX_DEPOSIT) {
      IERC20(ps.rewardToken).safeTransfer(winnerAddress, winnerAmount);
    } else {
      ps.participantDeposits[winnerAddress].amount = newWinnerTotalDeposit; // else add to winner's deposit
    }

    emit WinnerSelected(winnerAddress, winnerAmount, roundNum);

    // update last closed round
    ps.lastClosedRound = roundNum;
    ps.startTime = 0;
    ps.pausedTimeInRound = 0;
    ps.receivedRandomNumber = false;
  }

  function _selectWinner(
    PonzuStorage storage ps,
    uint256 randomNum,
    uint256 roundDeadline
  ) internal view returns (address winnerAddress) {
    uint256 totalParticipantsCount = ps.participantsList.length;
    uint256 totalDeposited = ps.totalDeposited;
    // divide number by total deposited
    uint256 winnerNumber = randomNum % totalDeposited;

    for (uint256 i = 0; i < totalParticipantsCount; ++i) {
      address participantAddress = ps.participantsList[i];
      uint256 pDeposit = ps.participantDeposits[participantAddress].amount;
      uint256 pTimestamp = ps.participantDeposits[participantAddress].timestamp;

      // check if valid deposit
      if (pTimestamp > roundDeadline) continue; // if deposit after deadline then skip

      if (pDeposit >= winnerNumber) return participantAddress;
      else winnerNumber -= pDeposit;
    }
    return address(0); // winner not found
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
}

