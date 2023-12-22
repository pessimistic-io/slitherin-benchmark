// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Strings} from "./Strings.sol";

import {LibPonzu} from "./LibPonzu.sol";
import {PonzuStorage, RoundWinner, ParticipantDeposit} from "./PonzuStorage.sol";
import {WithRoles} from "./LibAccessControl.sol";
import {DEFAULT_ADMIN_ROLE, GAME_ADMIN_ROLE} from "./AccessControlStorage.sol";
import {LibAccessControl} from "./LibAccessControl.sol";
import {PonzuRoundData} from "./PonzuRoundData.sol";

import {LibQRNG} from "./LibQRNG.sol";
import {QRNGStorage} from "./QRNGStorage.sol";

import {IHamachi} from "./IHamachi.sol";

contract PonzuFacet is WithRoles {
  using Strings for uint256;
  using LibPonzu for PonzuStorage;
  using LibQRNG for QRNGStorage;

  // ==================== Management ==================== //

  /// deposit allows the sender to deposit an amount of rewardToken
  function deposit(uint256 amount) external {
    PonzuStorage storage ps = LibPonzu.DS();
    ps.deposit(msg.sender, amount);
  }

  /// withdraw allows the sender to withdraw their deposited amount
  function withdraw(uint256 amount) external {
    PonzuStorage storage ps = LibPonzu.DS();
    ps.withdraw(msg.sender, amount);
  }

  /// addSauce allows the sender to adds more sauce to the prizePool
  function addSauce(uint256 amount) external {
    PonzuStorage storage ps = LibPonzu.DS();
    ps.addRewards(msg.sender, amount);
  }

  /// claimsReward claims the pending rewards in rewardToken, filling the prizepool
  function claimReward() external {
    PonzuStorage storage ps = LibPonzu.DS();
    ps.claimRewards();
  }

  // ==================== Game Admin Management ==================== //

  function startRound(uint256 startTime) external onlyRole(GAME_ADMIN_ROLE) {
    PonzuStorage storage ps = LibPonzu.DS();
    ps.startRound(startTime);
  }

  // ==================== Admin Management ==================== //

  function setDefaultAdminRole(address user) external onlyRole(DEFAULT_ADMIN_ROLE) {
    LibAccessControl.grantRole(DEFAULT_ADMIN_ROLE, user);
  }

  // Allows the contract to toggle the claim type of the reward token
  function manualClaim(bool _manual) external onlyRole(DEFAULT_ADMIN_ROLE) {
    PonzuStorage storage ps = LibPonzu.DS();
    IHamachi(ps.rewardToken).setManualClaim(_manual);
  }

  function setRoundSettings(
    uint256 _depositDeadline,
    uint256 _roundDuration
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    PonzuStorage storage ps = LibPonzu.DS();
    ps.depositDeadline = _depositDeadline;
    ps.roundDuration = _roundDuration;
  }

  function setRewardToken(address _rewardTokenAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
    PonzuStorage storage ps = LibPonzu.DS();
    ps.rewardToken = _rewardTokenAddress;
  }

  function setBlackHole(address _blackHoleAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
    PonzuStorage storage ps = LibPonzu.DS();
    ps.blackHole = _blackHoleAddress;
  }

  function setBlackHoleShare(uint256 _share) external onlyRole(DEFAULT_ADMIN_ROLE) {
    PonzuStorage storage ps = LibPonzu.DS();
    ps.blackHoleShare = _share;
  }

  // ==================== Views ==================== //

  function getRewardToken() external view returns (address) {
    PonzuStorage storage ps = LibPonzu.DS();
    return ps.rewardToken;
  }

  function getRoundSettings() external view returns (uint256, uint256) {
    PonzuStorage storage ps = LibPonzu.DS();
    return (ps.depositDeadline, ps.roundDuration);
  }

  function getBlackHole() external view returns (address) {
    PonzuStorage storage ps = LibPonzu.DS();
    return ps.blackHole;
  }

  function getBlackHoleShare() external view returns (uint256) {
    PonzuStorage storage ps = LibPonzu.DS();
    return ps.blackHoleShare;
  }

  function getCurrentStoredRewards() external view returns (uint256) {
    PonzuStorage storage ps = LibPonzu.DS();
    return ps.currentStoredRewards;
  }

  function getCurrentRoundData() external view returns (PonzuRoundData memory) {
    PonzuStorage storage ps = LibPonzu.DS();

    (
      uint256 currentRound,
      uint256 curRoundStartTime,
      uint256 curRoundDeadline,
      uint256 curRoundEndTime
    ) = ps.currentRoundTimes();

    return
      PonzuRoundData({
        lastClosedRound: ps.lastClosedRound,
        currentRoundNumber: currentRound,
        currentRoundStartTime: curRoundStartTime,
        currentRoundDeadline: curRoundDeadline,
        currentRoundEndTime: curRoundEndTime,
        currentStoredRewards: ps.currentStoredRewards,
        currentRoundPrizePool: ps.currentPrizePool(),
        currentRoundPonzuPool: ps.totalDeposited,
        totalParticipants: ps.participantsList.length
      });
  }

  function getRoundWinnerData(uint256 _roundNumber) external view returns (RoundWinner memory) {
    PonzuStorage storage ps = LibPonzu.DS();
    return ps.roundWinners[_roundNumber];
  }

  function prizePool() external view returns (uint256) {
    PonzuStorage storage ps = LibPonzu.DS();
    return ps.currentPrizePool();
  }

  function ponzuPool() external view returns (uint256) {
    PonzuStorage storage ps = LibPonzu.DS();
    return ps.totalDeposited;
  }

  function currentRoundInfo() external view returns (uint256, uint256, uint256, uint256) {
    PonzuStorage storage ps = LibPonzu.DS();
    return ps.currentRoundTimes();
  }

  function totalParticipants() external view returns (uint256) {
    PonzuStorage storage ps = LibPonzu.DS();
    return ps.participantsList.length;
  }

  function getParticipantList() external view returns (address[] memory) {
    PonzuStorage storage ps = LibPonzu.DS();
    return ps.participantsList;
  }

  function getParticipantDeposit(address _account) external view returns (uint256, uint256) {
    PonzuStorage storage ps = LibPonzu.DS();
    ParticipantDeposit memory participantDeposit = ps.participantDeposits[_account];
    return (participantDeposit.timestamp, participantDeposit.amount);
  }

  function getPausedTimeInRound() external view returns (uint256) {
    PonzuStorage storage ps = LibPonzu.DS();
    return ps.pausedTimeInRound;
  }
}

