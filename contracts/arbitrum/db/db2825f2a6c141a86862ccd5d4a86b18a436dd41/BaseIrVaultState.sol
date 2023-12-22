//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IERC20 } from "./IERC20.sol";

contract BaseIrVaultState {
  struct Addresses {
    address optionPricing;
    address gaugeOracle;
    address volatilityOracle;
    address crv;
    address curvePoolGauge;
    address feeStrategy;
    address feeDistributor;
    address crvLP;
    address crv2PoolGauge;
    address crvChildGauge;
  }

  struct UserStrikeDeposits {
    uint256 amount;
    uint256 callLeverage;
    uint256 putLeverage;
  }

  struct UserStrikePurchaseData {
    uint256 putsPurchased;
    uint256 callsPurchased;
    uint256 userEpochCallsPremium;
    uint256 userEpochPutsPremium;
  }

  struct StrikeData {
    uint256 totalTokensStrikeDeposits;
    uint256 totalCallsStrikeDeposits;
    uint256 totalPutsStrikeDeposits;
    uint256 totalCallsPurchased;
    uint256 totalPutsPurchased;
    uint256 callsSettlement;
    uint256 putsSettlement;
    uint256[] leveragedCallsDeposits;
    uint256[] leveragedPutsDeposits;
    uint256[] totalCallsStrikeBalance;
    uint256[] totalPutsStrikeBalance;
  }

  struct EpochData {
    uint256 totalCallsDeposits;
    uint256 totalPutsDeposits;
    uint256 totalTokenDeposits;
    uint256 epochCallsPremium;
    uint256 epochPutsPremium;
    uint256 totalCallsPurchased;
    uint256 totalPutsPurchased;
    uint256 epochStartTimes;
    uint256 epochExpiryTime;
    bool isEpochExpired;
    bool isVaultReady;
    uint256 epochBalanceAfterUnstaking;
    uint256 crvToDistribute;
    uint256 rateAtSettlement;
    uint256[] epochStrikes;
    uint256[] callsLeverages;
    uint256[] putsLeverages;
    address[] callsToken;
    address[] putsToken;
    uint256[] epochStrikeCallsPremium;
    uint256[] epochStrikePutsPremium;
  }

  /// @dev Current epoch for ssov
  uint256 public currentEpoch;

  /// @dev Contract addresses
  Addresses public addresses;

  /// @dev Expire delay tolerance
  uint256 public expireDelayTolerance = 5 minutes;

  /// @notice Epoch deposits by user for each strike
  /// @dev mapping (epoch => (abi.encodePacked(user, strike, callLeverage, putLeverage) => user deposits))
  mapping(uint256 => mapping(bytes32 => UserStrikeDeposits))
    public userEpochStrikeDeposits;

  /// @notice Puts purchased by user for each strike
  /// @dev mapping (epoch => (abi.encodePacked(user, strike) => user puts purchased))
  mapping(uint256 => mapping(bytes32 => UserStrikePurchaseData))
    public userStrikePurchaseData;

  /// @notice Total epoch deposits for specific strikes
  /// @dev mapping (epoch =>  StrikeDeposits))
  mapping(uint256 => EpochData) public totalEpochData;

  /// @notice Total epoch deposits for specific strikes
  /// @dev mapping (epoch => (strike => StrikeDeposits))
  mapping(uint256 => mapping(uint256 => StrikeData)) public totalStrikeData;

  /*==== ERRORS & EVENTS ====*/

  event ExpireDelayToleranceUpdate(uint256 expireDelayTolerance);

  event WindowSizeUpdate(uint256 windowSizeInHours);

  event AddressesSet(Addresses addresses);

  event EmergencyWithdraw(address sender);

  event EpochExpired(address sender, uint256 rateAtSettlement);

  event StrikeSet(uint256 epoch, uint256 strike);

  event CallsLeverageSet(uint256 epoch, uint256 leverage);

  event PutsLeverageSet(uint256 epoch, uint256 leverage);

  event Bootstrap(uint256 epoch);

  event Deposit(
    uint256 epoch,
    uint256 strike,
    uint256 amount,
    address user,
    address sender
  );

  event Purchase(
    uint256 epoch,
    uint256 strike,
    uint256 amount,
    uint256 premium,
    uint256 fee,
    address user
  );

  event Settle(
    uint256 epoch,
    uint256 strike,
    address user,
    uint256 amount,
    uint256 pnl, // pnl transfered to the user
    uint256 fee // fee sent to fee distributor
  );

  event Compound(
    uint256 epoch,
    uint256 rewards,
    uint256 oldBalance,
    uint256 newBalance
  );

  event Withdraw(
    uint256 epoch,
    uint256 strike,
    address user,
    uint256 userDeposits,
    uint256 crvLPWithdrawn,
    uint256 crvRewards
  );

  error ZeroAddress(bytes32 source, address destination);
}

