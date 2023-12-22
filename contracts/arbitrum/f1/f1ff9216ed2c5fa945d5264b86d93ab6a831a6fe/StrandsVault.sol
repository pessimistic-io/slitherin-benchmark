//SPDX-License-Identifier: MIT
// StrandsVault.sol v1.0b
pragma solidity ^0.8.16;
import {Ownable} from "./Ownable.sol";
import {IERC20} from "./ERC20_IERC20.sol";
import {OptionMarket} from "./OptionMarket.sol";
import {BaseVault} from "./BaseVault.sol";
import {OwnableAdmins} from "./OwnableAdmins.sol";
import {Vault} from "./Vault.sol";

import {IStrandsStrategy} from "./IStrandsStrategy.sol";
import "./console.sol";


/// @notice StrandsVault help users run option-selling strategies on Lyra AMM.
contract StrandsVault is BaseVault {
  IERC20 public immutable quoteAsset;
  uint internal roundDelay = 1 minutes;
  string public underlier;
  uint public roundEnds;
  uint public timeBetweenRoundEndAndExpiry;

  IStrandsStrategy public strategy;
  address public lyraRewardRecipient;

  // Amount locked for scheduled withdrawals last week;
  uint public lastQueuedWithdrawAmount;
  // % of funds to be used for weekly option purchase
  uint public optionAllocation;

  event StrategyUpdated(address strategy);

  event Trade(address user, uint[] tradePositionIds, int tradeCost);

  event Hedge(address user, uint[] hedgePositionIds, int hedgeCost);

  event RoundStarted(uint16 roundId, uint104 lockAmount,uint newPricePerShare,uint roundEnds);

  event RoundClosed(uint16 roundId, uint104 lockAmount);

  constructor(
    address _quoteAssetAddress,
    address _feeRecipient,
    uint _roundDuration,
    string memory _tokenName,
    string memory _tokenSymbol,
    string memory _underlier,
    Vault.VaultParams memory _vaultParams
  ) BaseVault(_feeRecipient, _roundDuration, _tokenName, _tokenSymbol, _vaultParams) {
    quoteAsset = IERC20(_quoteAssetAddress);
    underlier=_underlier;
  }

  /// @dev set strategy contract. This function can only be called by owner.
  /// @param _strategy new strategy contract address
  function setStrategy(address _strategy) external onlyAdmins {
    if (address(strategy) != address(0)) {
      quoteAsset.approve(address(strategy), 0);
    }

    strategy = IStrandsStrategy(_strategy);
    quoteAsset.approve(address(_strategy), type(uint).max);
    emit StrategyUpdated(_strategy);
  }

  /// @param strikeId the strike id to sell
  function trade(uint strikeId) external onlyAdmins {
    require(vaultState.roundInProgress, "round closed");
    // perform trade through strategy
    (int balChange, uint[] memory tradePositionIds) = strategy.doTrade(strikeId);
    vaultState.lockedAmountLeft = uint(int(vaultState.lockedAmountLeft) + balChange);
    console.log("lockedAmontLeft after trade=%s",vaultState.lockedAmountLeft);
    emit Trade(msg.sender, tradePositionIds, balChange);
  }

  function deltaHedge(uint hedgeType) external onlyAdmins {
    require(vaultState.roundInProgress, "round closed");
    _deltaHedge(hedgeType);
  }

  function _deltaHedge(uint hedgeType) internal {  
    (int balChange, uint[] memory hedgePositionIds) = strategy.deltaHedge(hedgeType);
    vaultState.lockedAmountLeft = uint(int(vaultState.lockedAmountLeft) + balChange);
    console.log("lockedAmontLeft after deltaHedge=%s",vaultState.lockedAmountLeft);
    emit Hedge(msg.sender, hedgePositionIds, balChange);
  }

  function reducePosition(uint closeAmount) external onlyAdmins {
    (int balChange, uint[] memory positionIds) = strategy.reducePosition(closeAmount);
    vaultState.lockedAmountLeft = uint(int(vaultState.lockedAmountLeft) + balChange);
    emit Hedge(msg.sender, positionIds, balChange);
  }

  function closeAllPositions() public onlyAdmins {
    require(vaultState.roundInProgress, "round not in progress");
    int balChange = strategy.emergencyCloseAll();
    vaultState.lockedAmountLeft = uint(int(vaultState.lockedAmountLeft) + balChange);
  }

  /// @dev close the current round, enable user to deposit for the next round
  function closeRound() external onlyAdmins {
    require(vaultState.roundInProgress, "round not in progress");
    require(!strategy.hasOpenPosition(),"has open position(s)");

    uint104 lockAmount = vaultState.lockedAmount;
    vaultState.lastLockedAmount = lockAmount;
    vaultState.lockedAmountLeft = 0;
    vaultState.lockedAmount = 0;
    vaultState.nextRoundReadyTimestamp = block.timestamp + roundDelay;
    vaultState.roundInProgress = false;

    strategy.returnFundsToVault();

    emit RoundClosed(vaultState.round, lockAmount);
  }

  /// @dev Close the current round, enable user to deposit for the next round
  //       Can call multiple times before round starts to close all positions
  function emergencyCloseRound() external onlyAdmins {
    require(vaultState.roundInProgress, "round not in progress");

    closeAllPositions();
    uint104 lockAmount = vaultState.lockedAmount;
    vaultState.lastLockedAmount = lockAmount;
    vaultState.lockedAmountLeft = 0;
    vaultState.lockedAmount = 0;
    vaultState.nextRoundReadyTimestamp = block.timestamp + roundDelay;
    vaultState.roundInProgress = false;
    emit RoundClosed(vaultState.round, lockAmount);
  }

  /// @notice start the next round
  /// @param boardId board id (asset + expiry) for next round.
  function startNextRound(uint boardId) external onlyAdmins {
    require(!vaultState.roundInProgress, "round in progress");
    require(block.timestamp > vaultState.nextRoundReadyTimestamp, "Delay between rounds not elapsed");
    roundEnds = strategy.setBoard(boardId);
    (uint lockedBalance, uint queuedWithdrawAmount,uint newPricePerShare) = _rollToNextRound();
    console.log("new round lockedBalance=%s/100",lockedBalance/10**16);
    vaultState.lockedAmount = uint104(lockedBalance);
    vaultState.lockedAmountLeft = lockedBalance;
    vaultState.roundInProgress = true;
    lastQueuedWithdrawAmount = queuedWithdrawAmount;

    emit RoundStarted(vaultState.round, uint104(lockedBalance),newPricePerShare,roundEnds);
  }

  /// @notice set new address to receive Lyra trading reward on behalf of the vault
  /// @param recipient recipient address
  function setLyraRewardRecipient(address recipient) external onlyAdmins {
    lyraRewardRecipient = recipient;
  }

  /// @notice set minimal time between stop and start of rounds
  /// @param _roundDelay in seconds
  function setRoundDelay(uint _roundDelay) external onlyAdmins {
    roundDelay = _roundDelay;
  }
}

