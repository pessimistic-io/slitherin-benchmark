// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC20.sol";

import "./FloatingPointConstants.sol";

import "./ILiquidityStaker.sol";

import "./ManagerModifier.sol";

contract BattleBoost is ManagerModifier {
  ILiquidityStaker public liquidityStaker;
  ERC20 public liquidityToken;

  //=======================================
  // Uints
  //=======================================
  uint256 public ANIMA_BASE_PER_THRESHOLD = 0.05 ether;
  uint256[] public THRESHOLDS = [10, 100, 500, 1000, 3000, 5000];

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ManagerModifier(_manager) {}

  //=======================================
  // External
  //=======================================
  function getAnimaBase(
    address staker
  ) external view returns (uint256 baseAnima) {
    if (
      address(liquidityToken) == address(0) ||
      address(liquidityStaker) == address(0)
    ) {
      return baseAnima;
    }

    uint256 totalSupply = liquidityToken.totalSupply();
    uint256 cap = (THRESHOLDS[THRESHOLDS.length - 1] * totalSupply) /
      ONE_HUNDRED;

    StakerBalance memory balance = liquidityStaker.currentStatusTotal(
      staker,
      cap
    );
    return calculateAnimaBase(balance, totalSupply);
  }

  function getSimulatedAnimaBase(
    uint256 _fullyVestedBalance
  ) external view returns (uint256 baseAnima) {
    if (
      address(liquidityToken) == address(0) ||
      address(liquidityStaker) == address(0)
    ) {
      return baseAnima;
    }

    uint256 totalSupply = liquidityToken.totalSupply();
    uint256 cap = (THRESHOLDS[THRESHOLDS.length - 1] * totalSupply) /
      ONE_HUNDRED;

    StakerBalance memory balance;
    balance.cap = cap;
    balance.uncappedDepositedBalance = _fullyVestedBalance;
    balance.cappedDepositedBalance = cap < _fullyVestedBalance
      ? cap
      : _fullyVestedBalance;
    balance.fullyVestedBalance = balance.cappedDepositedBalance;
    balance.totalUncappedBalance = balance.uncappedDepositedBalance;

    return calculateAnimaBase(balance, totalSupply);
  }

  function calculateAnimaBase(
    StakerBalance memory _balance,
    uint256 _totalSupply
  ) internal view returns (uint256 baseAnima) {
    uint256 unvestedDeposit = _balance.cappedDepositedBalance -
      _balance.fullyVestedBalance;
    for (uint256 i = 0; i < THRESHOLDS.length; i++) {
      uint256 thresholdAmount = (THRESHOLDS[i] * _totalSupply) / ONE_HUNDRED;
      if (_balance.cappedDepositedBalance < thresholdAmount) {
        return baseAnima;
      }

      if (_balance.fullyVestedBalance >= thresholdAmount) {
        baseAnima += ANIMA_BASE_PER_THRESHOLD;
      } else {
        baseAnima +=
          (ANIMA_BASE_PER_THRESHOLD * _balance.partiallyVestedBalance) /
          unvestedDeposit;
      }
    }
    return baseAnima;
  }

  //=======================================
  // Admin
  //=======================================
  function setContracts(
    address _lpToken,
    address _lpStaker
  ) external onlyAdmin {
    liquidityStaker = ILiquidityStaker(_lpStaker);
    liquidityToken = ERC20(_lpToken);
  }
}

