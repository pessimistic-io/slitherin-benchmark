// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./Math.sol";
import "./SafeERC20.sol";
import "./IUnderlying.sol";
import "./IVoter.sol";
import "./IVe.sol";
import "./IVeDist.sol";
import "./IMinter.sol";
import "./IERC20.sol";
import "./IController.sol";

/// @title Codifies the minting rules as per ve(3,3),
///        abstracted from the token to support any token that allows minting
contract LizardMinter is IMinter {
  using SafeERC20 for IERC20;

  /// @dev Allows minting once per week (reset every Thursday 00:00 UTC)
  uint internal constant _WEEK = 86400 * 7;
  uint internal constant _LOCK_PERIOD = 86400 * 7 * 52 * 4;

  /// @dev Decrease base weekly emission by 2%
  uint internal constant _WEEKLY_EMISSION_DECREASE = 97;
  uint internal constant _WEEKLY_EMISSION_DECREASE_DENOMINATOR = 100;


  /// @dev Weekly emission threshold for the end game. 1% of circulation supply.
  uint internal constant _TAIL_EMISSION = 1;
  uint internal constant _TAIL_EMISSION_DENOMINATOR = 100;

  /// @dev Decrease weekly rewards for ve holders. 50% of the full amount.
  uint internal constant _GROWTH_DIVIDER = 2;

  /// @dev Decrease initialStubCirculationSupply by 1% per week.
  ///      Decreasing only if circulation supply lower that the stub circulation
  uint internal constant _INITIAL_CIRCULATION_DECREASE = 99;
  uint internal constant _INITIAL_CIRCULATION_DECREASE_DENOMINATOR = 100;

  /// @dev Stubbed initial circulating supply to avoid first weeks gaps of locked amounts.
  ///      Should be equal expected unlocked token percent.
  uint internal constant _STUB_CIRCULATION = 10;
  uint internal constant _STUB_CIRCULATION_DENOMINATOR = 100;

  /// @dev The core parameter for determinate the whole emission dynamic.
  ///       Will be decreased every week.
  uint internal constant _START_BASE_WEEKLY_EMISSION = 15_000_000e18;
  /// @dev 5% goes to governance to maintain the platform.
  uint internal constant _GOVERNANCE_ALLOC = 20;


  IUnderlying public immutable token;
  IVe public immutable ve;
  address public immutable controller;
  uint public baseWeeklyEmission = _START_BASE_WEEKLY_EMISSION;
  uint public initialStubCirculation;
  uint public activePeriod;

  address internal initializer;

  event Mint(
    address indexed sender,
    uint weekly,
    uint growth,
    uint circulatingSupply,
    uint circulatingEmission
  );

  constructor(
    address ve_, // the ve(3,3) system that will be locked into
    address controller_ // controller with veDist and voter addresses
  ) {
    initializer = msg.sender;
    token = IUnderlying(IVe(ve_).token());
    ve = IVe(ve_);
    controller = controller_;
  }

  /// @dev Mint initial supply to holders and lock it to ve token.
  function initialize(
    address[] memory claimants,
    uint[] memory amounts,
    uint totalAmount,
    uint warmingUpPeriod // use 0 period only for testing purposes! ve holders should have time for voting
  ) external {
    require(initializer == msg.sender, "Not initializer");
    token.mint(address(this), totalAmount);
    token.mint(IController(controller).governance(), totalAmount / _GOVERNANCE_ALLOC);
    initialStubCirculation = totalAmount * _STUB_CIRCULATION / _STUB_CIRCULATION_DENOMINATOR;
    token.approve(address(ve), type(uint).max);
    uint sum;
    for (uint i = 0; i < claimants.length; i++) {
      ve.createLockFor(amounts[i], _LOCK_PERIOD, claimants[i]);
      sum += amounts[i];
    }
    require(sum == totalAmount, "Wrong totalAmount");
    initializer = address(0);
    activePeriod = block.timestamp / _WEEK * _WEEK + (warmingUpPeriod * _WEEK);
  }

  function _veDist() internal view returns (IVeDist) {
    return IVeDist(IController(controller).veDist());
  }

  function _voter() internal view returns (IVoter) {
    return IVoter(IController(controller).voter());
  }

  /// @dev Calculate circulating supply as total token supply - locked supply - veDist balance - minter balance
  function circulatingSupply() public view returns (uint) {
    return token.totalSupply() - IUnderlying(address(ve)).totalSupply()
    // exclude veDist token balance from circulation - users unable to claim them without lock
    // late claim will lead to wrong circulation supply calculation
    - token.balanceOf(address(_veDist()))
    // exclude balance on minter, it is obviously locked
    - token.balanceOf(address(this));
  }

  function circulatingSupplyAdjusted() public view returns (uint) {
    // we need a stub supply for cover initial gap when huge amount of tokens was distributed and locked
    return Math.max(circulatingSupply(), initialStubCirculation);
  }

  /// @dev Emission calculation is 2% of available supply to mint adjusted by circulating / total supply
  function calculateEmission() public view returns (uint) {
    // use adjusted circulation supply for avoid first weeks gaps
    // baseWeeklyEmission should be decrease every week
    return baseWeeklyEmission * circulatingSupplyAdjusted() / token.totalSupply();
  }

  /// @dev Weekly emission takes the max of calculated (aka target) emission versus circulating tail end emission
  function weeklyEmission() public view returns (uint) {
    return Math.max(calculateEmission(), circulatingEmission());
  }

  /// @dev Calculates tail end (infinity) emissions as 0.2% of total supply
  function circulatingEmission() public view returns (uint) {
    return circulatingSupply() * _TAIL_EMISSION / _TAIL_EMISSION_DENOMINATOR;
  }

  /// @dev Calculate inflation and adjust ve balances accordingly
  function calculateGrowth(uint _minted) public view returns (uint) {
    return IUnderlying(address(ve)).totalSupply() * _minted / token.totalSupply() / _GROWTH_DIVIDER;
  }

  /// @dev Update period can only be called once per cycle (1 week)
  function updatePeriod() external override {
    // only trigger if new week
    if (block.timestamp >= activePeriod && initializer == address(0)) {
      activePeriod = block.timestamp / _WEEK * _WEEK + _WEEK;
      uint _weekly = weeklyEmission();
      // slightly decrease weekly emission
      baseWeeklyEmission = baseWeeklyEmission
      * _WEEKLY_EMISSION_DECREASE
      / _WEEKLY_EMISSION_DECREASE_DENOMINATOR;
      // decrease stub supply every week if it higher than the real circulation
      if (initialStubCirculation > circulatingEmission()) {
        initialStubCirculation = initialStubCirculation
        * _INITIAL_CIRCULATION_DECREASE
        / _INITIAL_CIRCULATION_DECREASE_DENOMINATOR;
      }

      uint _growth = calculateGrowth(_weekly);
      uint toGovernance = (_growth + _weekly) / _GOVERNANCE_ALLOC;
      uint _required = _growth + _weekly + toGovernance;
      uint _balanceOf = token.balanceOf(address(this));
      if (_balanceOf < _required) {
        token.mint(address(this), _required - _balanceOf);
      }

      // send governance part
      IERC20(address(token)).safeTransfer(IController(controller).governance(), toGovernance);

      IVeDist veDist = _veDist();
      IVoter voter = _voter();

      IERC20(address(token)).safeTransfer(address(veDist), _growth);
      // checkpoint token balance that was just minted in veDist
      veDist.checkpointToken();
      // checkpoint supply
      veDist.checkpointTotalSupply();

      token.approve(address(voter), _weekly);
      voter.notifyRewardAmount(_weekly);

      emit Mint(msg.sender, _weekly, _growth, circulatingSupply(), circulatingEmission());
    }
  }

}

