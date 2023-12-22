// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import "./ERC20.sol";

import "./FloatingPointConstants.sol";

import "./ILiquidityStaker.sol";

import "./ManagerModifier.sol";
import "./IBattleBoost.sol";

struct LiquidityStakerConfig {
  address lpStaker;
  address lpToken;
  uint weight;
}

contract MultiLpBattleBoost is IBattleBoost, ManagerModifier {
  //=======================================
  // LP Configs
  //=======================================
  LiquidityStakerConfig[] public configs;

  //=======================================
  // Uints
  //=======================================
  uint256 public animaBasePerThreshold = 0.05 ether;
  uint256[] public thresholds = [10, 100, 500, 1000, 3000, 5000, 10000];

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ManagerModifier(_manager) {}

  //=======================================
  // External
  //=======================================
  function getAnimaBase(address _staker) external view returns (uint256) {
    if (configs.length == 0 || thresholds.length == 0) {
      return 0;
    }

    (
      uint256 fullyVestedPercentage,
      uint256 partiallyVestedPercentage,
      uint256 cappedDepositedPercentage
    ) = getTotalPercentage(_staker);
    return
      calculateAnimaBase(
        fullyVestedPercentage,
        partiallyVestedPercentage,
        cappedDepositedPercentage
      );
  }

  function getSimulatedAnimaBase(
    uint256[] calldata _fullyVestedTokens
  ) external view returns (uint256) {
    if (configs.length == 0 || thresholds.length == 0) {
      return 0;
    }

    require(
      _fullyVestedTokens.length == configs.length,
      "Invalid simulated token amount"
    );

    uint totalVested = 0;
    uint maxThreshold = thresholds[thresholds.length - 1];
    for (uint i = 0; i < _fullyVestedTokens.length; i++) {
      uint256 totalSupply = IERC20(configs[i].lpToken).totalSupply();
      uint256 cap = (maxThreshold * totalSupply) / configs[i].weight;
      totalVested += _fullyVestedTokens[i] > cap ? cap : _fullyVestedTokens[i];
    }

    return calculateAnimaBase(totalVested, 0, totalVested);
  }

  function getTotalPercentage(
    address staker
  )
    internal
    view
    returns (
      uint256 fullyVestedPercentage,
      uint256 partiallyVestedPercentage,
      uint256 cappedDepositedPercentage
    )
  {
    for (uint i = 0; i < configs.length; i++) {
      (
        uint partialFullyVested,
        uint partialVesting,
        uint partialCappedDeposit
      ) = getSingleVestedPercentage(staker, configs[i]);
      fullyVestedPercentage += partialFullyVested;
      partiallyVestedPercentage += partialVesting;
      cappedDepositedPercentage += partialCappedDeposit;
    }
  }

  function getSingleVestedPercentage(
    address staker,
    LiquidityStakerConfig storage config
  )
    internal
    view
    returns (
      uint256 fullyVestedWeight,
      uint256 partiallyVestedWeight,
      uint256 cappedDepositedWeight
    )
  {
    uint totalSupply = IERC20(config.lpToken).totalSupply();
    if (totalSupply == 0) {
      return (0, 0, 0);
    }
    uint256 cap = 1 +
      ((thresholds[thresholds.length - 1] * totalSupply) / config.weight);

    StakerBalance memory balance = ILiquidityStaker(config.lpStaker)
      .currentStatusTotal(staker, cap);

    fullyVestedWeight =
      (((DECIMAL_POINT * config.weight * balance.fullyVestedBalance) +
        ROUNDING_ADJUSTER) / totalSupply) /
      DECIMAL_POINT;
    partiallyVestedWeight =
      (((DECIMAL_POINT * config.weight * balance.partiallyVestedBalance) +
        ROUNDING_ADJUSTER) / totalSupply) /
      DECIMAL_POINT;
    cappedDepositedWeight =
      (((DECIMAL_POINT * config.weight * balance.cappedDepositedBalance) +
        ROUNDING_ADJUSTER) / totalSupply) /
      DECIMAL_POINT;
  }

  function calculateAnimaBase(
    uint256 fullyVested,
    uint256 partiallyVested,
    uint256 cappedDeposited
  ) internal view returns (uint256 baseAnima) {
    uint totalVested = fullyVested + partiallyVested;
    for (uint256 i = 0; i < thresholds.length; i++) {
      uint256 thresholdAmount = thresholds[i];
      if (cappedDeposited < thresholdAmount) {
        return baseAnima;
      }

      if (fullyVested >= thresholdAmount) {
        baseAnima += animaBasePerThreshold;
      } else {
        baseAnima += (animaBasePerThreshold * totalVested) / (cappedDeposited);
      }
    }
    return baseAnima;
  }

  //=======================================
  // Admin
  //=======================================
  function updateLiquidityConfig(
    LiquidityStakerConfig[] calldata _configs
  ) external onlyAdmin {
    while (configs.length > 0) {
      configs.pop();
    }

    for (uint i = 0; i < _configs.length; i++) {
      require(
        _configs[i].lpStaker != address(0) &&
          _configs[i].lpToken != address(0) &&
          _configs[i].weight != 0
      );

      // Check if the contracts conform to interfaces, reverts if views are not available
      ILiquidityStaker(_configs[i].lpStaker).currentStatusTotal(address(0), 0);
      IERC20(_configs[i].lpToken).totalSupply();
      configs.push(_configs[i]);
    }
  }

  function updateAnimaBasePerThreshold(uint256 _value) external onlyAdmin {
    animaBasePerThreshold = _value;
  }

  function updateThresholds(uint256[] calldata _thresholds) external onlyAdmin {
    thresholds = _thresholds;
  }
}

