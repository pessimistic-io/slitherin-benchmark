// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Math.sol";
import "./SafeERC20.sol";
import "./IUnderlying.sol";
import "./IVoter.sol";
import "./IVe.sol";
import "./IGauge.sol";
import "./IMinter.sol";
import "./IERC20.sol";
import "./IController.sol";

/// @title Codifies the minting rules as per ve(3,3),
///        abstracted from the token to support any token that allows minting
contract BurgerMinter is IMinter {
  using SafeERC20 for IERC20;

  uint internal numEpoch;

  /// @dev Allows minting once per week (reset every Thursday 00:00 UTC)
  uint internal constant _WEEK = 86400 * 7;
  uint internal constant _LOCK_PERIOD = 86400 * 7 * 26; // 26 weeks
  uint internal constant _LOCK_PARTNER = 86400 * 7 * 52; // 52 weeks (1 year)

  /// @dev Decrease base weekly emission by 0.5%
  uint public emissionValue = 995;
  uint internal constant _WEEKLY_EMISSION_DECREASE_DENOMINATOR = 1000;


  /// @dev Weekly emission threshold for the end game. 4% of locked supply.
  uint internal constant _LOCKED_EMISSION = 40;
  uint internal constant _LOCKED_EMISSION_DENOMINATOR = 1000;

  /// @dev Team weekly emission threshold for the end game. 2.5% of circulation supply.
  uint public teamRate = 25;
  /// @notice Gauge address for HAMBURGER/WETH pair
  address public hamburgerWethGauge;
  uint internal constant HAMBURGER_WETH_PAIR_RATE = 10;

  uint internal constant PRECISION = 1000;

  /// @dev The core parameter for determinate the whole emission dynamic.
  ///       Will be decreased every week.
  uint internal constant _START_BASE_WEEKLY_EMISSION = 50_000e18;


  IUnderlying public immutable token;
  IVe public immutable ve;
  address public immutable controller;
  uint public baseWeeklyEmission = _START_BASE_WEEKLY_EMISSION;
  uint public activePeriod;
  address public team;

  address internal initializer;

  event Mint(
    address indexed sender,
    uint weekly,
    uint circulatingSupply,
    uint circulatingEmission
  );

  constructor(
    address ve_, // the ve(3,3) system that will be locked into
    address controller_, // controller with voter addresses
    uint warmingUpPeriod // 2 by default
  ) {
    initializer = msg.sender;
    team = msg.sender;
    token = IUnderlying(IVe(ve_).token());
    ve = IVe(ve_);
    controller = controller_;
    activePeriod = (block.timestamp + (warmingUpPeriod * _WEEK)) / _WEEK * _WEEK;
  }

  /// @dev Mint initial supply to holders and lock it to ve token.
  function initialize(
    address[] memory claimants,
    uint[] memory amounts,
    uint totalAmount
  ) external {
    require(initializer == msg.sender, "Not initializer");
    token.mint(address(this), totalAmount);
    token.approve(address(ve), type(uint).max);
    uint sum;
    for (uint i = 0; i < claimants.length; i++) {
      ve.createLockForPartner(amounts[i], _LOCK_PARTNER, claimants[i]); // CREATE LOCK FOR PARTNER 1 YEAR
      sum += amounts[i];
    }
    require(sum == totalAmount, "Wrong totalAmount");
    initializer = address(0);
    activePeriod = 1681491600; // 04-14-2023 (so protocol starts dist tokens at 04-21-2023)
    // activePeriod = (block.timestamp / _WEEK) * _WEEK; // allow to start distributing rewards after 1 week from this timestamp
  }

  function setTeam(address _newTeam) external {
    require(msg.sender == team, "Not team");
    team = _newTeam;
  }

  function _voter() internal view returns (IVoter) {
    return IVoter(IController(controller).voter());
  }

  function setHamburgerWethGauge(address _hamburgerWethGauge) external {
    require(msg.sender == team, "not team");
    require(_hamburgerWethGauge != address(0), "zero address");
    hamburgerWethGauge = _hamburgerWethGauge;
  }

  /// @dev Calculate circulating supply as locked supply
  function lockedSupply() external view returns (uint) {
    return _lockedSupply();
  }

  function _lockedSupply() internal view returns (uint) {
    return IUnderlying(address(ve)).totalSupply();
  }

  function calculateEmission() external view returns (uint) {
    return _calculateEmission();
  }

  function _calculateEmission() internal view returns (uint) {
    // use adjusted circulation supply for avoid first weeks gaps
    // baseWeeklyEmission should be decrease every week
    return (baseWeeklyEmission * emissionValue) / PRECISION;
  }

  /// @dev Weekly emission takes the max of calculated (aka target) emission versus locked emission
  function weeklyEmission() external view returns (uint) {
    return _weeklyEmission();
  }

  function _weeklyEmission() internal view returns (uint) {
    return Math.max(_calculateEmission(), _lockedEmission());
  }

  /// @dev Calculates tail end (infinity) emissions as 0.2% of total supply
  function lockedEmission() external view returns (uint) {
    return _lockedEmission();
  }

  function _lockedEmission() internal view returns (uint) {
    return (_lockedSupply() * _LOCKED_EMISSION) / _LOCKED_EMISSION_DENOMINATOR;
  }

  /// @dev Update period can only be called once per cycle (1 week)
  function updatePeriod() external override returns (uint) {
    uint _period = activePeriod;
    // only trigger if new week
    if (block.timestamp >= _period + _WEEK && initializer == address(0)) {
      _period = block.timestamp / _WEEK * _WEEK;
      activePeriod = _period;
      uint _weekly = _weeklyEmission();
      // slightly decrease weekly emission
      baseWeeklyEmission = baseWeeklyEmission
      * emissionValue
      / _WEEKLY_EMISSION_DECREASE_DENOMINATOR;

      uint _teamEmissions = (teamRate * _weekly) / PRECISION;
      uint _hamburgerWethEmissions = (HAMBURGER_WETH_PAIR_RATE * _weekly) / PRECISION;
      uint _required = _weekly + _teamEmissions + _hamburgerWethEmissions;
      uint _balanceOf = token.balanceOf(address(this));
      if (_balanceOf < _required) {
        token.mint(address(this), _required - _balanceOf);
      }

      unchecked {
          ++numEpoch;
      }
      if (numEpoch == 104) emissionValue = 999;

      require(token.transfer(team, _teamEmissions));

      token.approve(address(_voter()), _weekly);
      _voter().notifyRewardAmount(_weekly);

      // new emissions for token/eth gauge
      token.approve(hamburgerWethGauge, _hamburgerWethEmissions);
      IGauge(hamburgerWethGauge).notifyRewardAmount(address(token), _hamburgerWethEmissions);

      emit Mint(msg.sender, _weekly, _lockedSupply(), _lockedEmission());
    }
    return _period;
  }

}

