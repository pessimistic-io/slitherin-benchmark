// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./ISolidlyRouter.sol";
import "./ISolidlyPair.sol";
import "./IRewardPool.sol";
import "./IGaugeStaker.sol";
import "./IGauge.sol";
import "./IERC20Extended.sol";
import "./StratManagerUpgradeable.sol";
import "./DynamicFeeManager.sol";

contract StrategyCommonSolidlyStakerLP is StratManagerUpgradeable, DynamicFeeManager {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  // Tokens used
  address public native;
  address public output;
  address public want;
  address public lpToken0;
  address public lpToken1;

  // Third party contracts
  address public gauge;
  address public gaugeStaker;

  address[] public rewards;

  bool public stable;
  bool public harvestOnDeposit;
  bool public spiritHarvest;
  uint256 public lastHarvest;
  uint256 public feeOnProfits;

  // Routes
  ISolidlyRouter.Routes[] public outputToNativeRoute;
  ISolidlyRouter.Routes[] public outputToLp0Route;
  ISolidlyRouter.Routes[] public outputToLp1Route;

  event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
  event Deposit(uint256 tvl);
  event Withdraw(uint256 tvl);
  event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

  function initialize(
    address _want,
    address _gauge,
    address _gaugeStaker,
    ISolidlyRouter.Routes[] memory _outputToNativeRoute,
    ISolidlyRouter.Routes[] memory _outputToLp0Route,
    ISolidlyRouter.Routes[] memory _outputToLp1Route,
    address[] memory _addresses
  ) public initializer {
    feeOnProfits = 50;
    __Ownable_init_unchained();
    __Pausable_init_unchained();
    __DynamicFeeManager_init();
    __StratManager_init_unchained(_addresses[0], _addresses[1], _addresses[2], _addresses[3], _addresses[4]);
    want = _want;
    gauge = _gauge;
    gaugeStaker = _gaugeStaker;

    stable = ISolidlyPair(want).stable();

    for (uint256 i; i < _outputToNativeRoute.length; ++i) {
      outputToNativeRoute.push(_outputToNativeRoute[i]);
    }

    for (uint256 i; i < _outputToLp0Route.length; ++i) {
      outputToLp0Route.push(_outputToLp0Route[i]);
    }

    for (uint256 i; i < _outputToLp1Route.length; ++i) {
      outputToLp1Route.push(_outputToLp1Route[i]);
    }

    output = outputToNativeRoute[0].from;
    native = outputToNativeRoute[outputToNativeRoute.length - 1].to;
    lpToken0 = outputToLp0Route[outputToLp0Route.length - 1].to;
    lpToken1 = outputToLp1Route[outputToLp1Route.length - 1].to;
    rewards.push(output);

    _giveAllowances();
  }

  // puts the funds to work
  function deposit() public whenNotPaused {
    uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));

    if (wantBal > 0) {
      IGaugeStaker(gaugeStaker).deposit(gauge, wantBal);
      emit Deposit(balanceOf());
    }
  }

  function withdraw(uint256 _amount) external {
    require(msg.sender == vault, "!vault");

    uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));

    if (wantBal < _amount) {
      IGaugeStaker(gaugeStaker).withdraw(gauge, _amount - wantBal);
      wantBal = IERC20Upgradeable(want).balanceOf(address(this));
    }

    if (wantBal > _amount) {
      wantBal = _amount;
    }

    if (tx.origin != owner() && !paused()) {
      uint256 withdrawalFeeAmount = (wantBal * withdrawalFee) / WITHDRAWAL_MAX;
      wantBal = wantBal - withdrawalFeeAmount;
    }

    IERC20Upgradeable(want).safeTransfer(vault, wantBal);

    emit Withdraw(balanceOf());
  }

  function beforeDeposit() external virtual override {
    if (harvestOnDeposit) {
      require(msg.sender == vault, "!vault");
      _harvest(tx.origin);
    }
  }

  function harvest() external virtual {
    _harvest(tx.origin);
  }

  function harvest(address callFeeRecipient) external virtual {
    _harvest(callFeeRecipient);
  }

  function managerHarvest() external onlyManager {
    _harvest(tx.origin);
  }

  // compounds earnings and charges performance fee
  function _harvest(address callFeeRecipient) internal whenNotPaused {
    IGaugeStaker(gaugeStaker).harvestRewards(gauge, rewards);
    uint256 outputBal = IERC20Upgradeable(output).balanceOf(address(this));
    if (outputBal > 0) {
      chargeFees(callFeeRecipient);
      addLiquidity();
      uint256 wantHarvested = balanceOfWant();
      deposit();

      lastHarvest = block.timestamp;
      emit StratHarvest(msg.sender, wantHarvested, balanceOf());
    }
  }

  // performance fees
  function chargeFees(address callFeeRecipient) internal {
    uint256 generalFeeOnProfits = (IERC20Upgradeable(output).balanceOf(address(this)) * feeOnProfits) / 1000;
    uint256 lockAmount = (generalFeeOnProfits / 2);
    generalFeeOnProfits = generalFeeOnProfits - lockAmount;

    uint256 generalFeeAmount;
    if (generalFeeOnProfits > 0) {
      if (output != native) {
        uint256 nativeBeforeSwap = IERC20Upgradeable(native).balanceOf(address(this));
        uint256 getAmountOut = ISolidlyRouter(dystRouter).getAmountsOut(generalFeeOnProfits, outputToNativeRoute)[
          outputToNativeRoute.length
        ];
        ISolidlyRouter(dystRouter).swapExactTokensForTokens(
          generalFeeOnProfits,
          getAmountOut,
          outputToNativeRoute,
          address(this),
          block.timestamp
        );
        generalFeeAmount = IERC20Upgradeable(native).balanceOf(address(this)) - nativeBeforeSwap;
      } else {
        generalFeeAmount = generalFeeOnProfits;
      }
    }

    uint256 callFeeAmount = (generalFeeAmount * callFee) / MAX_FEE;
    if (callFeeAmount > 0) {
      IERC20Upgradeable(native).safeTransfer(callFeeRecipient, callFeeAmount);
    }

    // Calculating the Fee to be distributed
    uint256 feeAmount1 = (generalFeeAmount * fee1) / MAX_FEE;
    uint256 feeAmount2 = (generalFeeAmount * fee2) / MAX_FEE;
    uint256 strategistFeeAmount = (generalFeeAmount * strategistFee) / MAX_FEE;

    // Transfer fees to recipients
    if (feeAmount1 > 0) {
      IERC20Upgradeable(native).safeTransfer(feeRecipient1, feeAmount1);
    }
    if (feeAmount2 > 0) {
      IERC20Upgradeable(native).safeTransfer(feeRecipient2, feeAmount2);
    }
    if (strategistFeeAmount > 0) {
      IERC20Upgradeable(native).safeTransfer(strategist, strategistFeeAmount);
    }
    IERC20Upgradeable(output).safeApprove(gaugeStaker, lockAmount);
    IGaugeStaker(gaugeStaker).lockHarvestAmount(gauge, lockAmount);
  }

  // Adds liquidity to AMM and gets more LP tokens.
  function addLiquidity() internal virtual {
    uint256 outputBal = IERC20Upgradeable(output).balanceOf(address(this));
    uint256 lp0Amt = outputBal / 2;
    uint256 lp1Amt = outputBal - lp0Amt;

    if (stable) {
      uint256 lp0Decimals = 10**IERC20Extended(lpToken0).decimals();
      uint256 lp1Decimals = 10**IERC20Extended(lpToken1).decimals();
      uint256 out0 = lpToken0 != output
        ? (ISolidlyRouter(dystRouter).getAmountsOut(lp0Amt, outputToLp0Route)[outputToLp0Route.length] * 1e18) /
          lp0Decimals
        : lp0Amt;
      uint256 out1 = lpToken1 != output
        ? (ISolidlyRouter(dystRouter).getAmountsOut(lp1Amt, outputToLp1Route)[outputToLp1Route.length] * 1e18) /
          lp1Decimals
        : lp0Amt;
      (uint256 amountA, uint256 amountB, ) = ISolidlyRouter(dystRouter).quoteAddLiquidity(
        lpToken0,
        lpToken1,
        stable,
        out0,
        out1
      );
      amountA = (amountA * 1e18) / lp0Decimals;
      amountB = (amountB * 1e18) / lp1Decimals;
      uint256 ratio = (((out0 * 1e18) / out1) * amountB) / amountA;
      lp0Amt = (outputBal * 1e18) / (ratio + 1e18);
      lp1Amt = outputBal - lp0Amt;
    }

    if (lpToken0 != output) {
      ISolidlyRouter(dystRouter).swapExactTokensForTokens(lp0Amt, 0, outputToLp0Route, address(this), block.timestamp);
    }

    if (lpToken1 != output) {
      ISolidlyRouter(dystRouter).swapExactTokensForTokens(lp1Amt, 0, outputToLp1Route, address(this), block.timestamp);
    }

    uint256 lp0Bal = IERC20Upgradeable(lpToken0).balanceOf(address(this));
    uint256 lp1Bal = IERC20Upgradeable(lpToken1).balanceOf(address(this));
    ISolidlyRouter(dystRouter).addLiquidity(
      lpToken0,
      lpToken1,
      stable,
      lp0Bal,
      lp1Bal,
      1,
      1,
      address(this),
      block.timestamp
    );
  }

  // calculate the total underlaying 'want' held by the strat.
  function balanceOf() public view returns (uint256) {
    return balanceOfWant() + balanceOfPool();
  }

  // it calculates how much 'want' this contract holds.
  function balanceOfWant() public view returns (uint256) {
    return IERC20Upgradeable(want).balanceOf(address(this));
  }

  // it calculates how much 'want' the strategy has working in the farm.
  function balanceOfPool() public view returns (uint256) {
    uint256 _amount = IGauge(gauge).balanceOf(gaugeStaker);
    return _amount;
  }

  // returns rewards unharvested
  function rewardsAvailable() public view returns (uint256) {
    return IGauge(gauge).earned(output, gaugeStaker);
  }

  function setGaugeStaker(address _gaugeStaker) external onlyOwner {
    panic();
    gaugeStaker = _gaugeStaker;
    unpause();
  }

  function setFeeOnProfits(uint256 _feeOnProfits) external onlyOwner {
    feeOnProfits = _feeOnProfits;
  }

  function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
    harvestOnDeposit = _harvestOnDeposit;

    if (harvestOnDeposit) {
      setWithdrawalFee(0);
    } else {
      setWithdrawalFee(10);
    }
  }

  // called as part of strat migration. Sends all the available funds back to the vault.
  function retireStrat() external {
    require(msg.sender == vault, "!vault");

    IGaugeStaker(gaugeStaker).withdraw(gauge, balanceOfPool());

    uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
    IERC20Upgradeable(want).transfer(vault, wantBal);
  }

  // pauses deposits and withdraws all funds from third party systems.
  function panic() public onlyManager {
    pause();
    IGaugeStaker(gaugeStaker).withdraw(gauge, balanceOfPool());
  }

  function pause() public onlyManager {
    _pause();

    _removeAllowances();
  }

  function unpause() public onlyManager {
    _unpause();

    _giveAllowances();

    deposit();
  }

  function _giveAllowances() internal {
    IERC20Upgradeable(want).safeApprove(gaugeStaker, type(uint256).max);
    IERC20Upgradeable(output).safeApprove(dystRouter, type(uint256).max);

    IERC20Upgradeable(lpToken0).safeApprove(dystRouter, 0);
    IERC20Upgradeable(lpToken0).safeApprove(dystRouter, type(uint256).max);

    IERC20Upgradeable(lpToken1).safeApprove(dystRouter, 0);
    IERC20Upgradeable(lpToken1).safeApprove(dystRouter, type(uint256).max);
  }

  function _removeAllowances() internal {
    IERC20Upgradeable(want).safeApprove(gaugeStaker, 0);
    IERC20Upgradeable(output).safeApprove(dystRouter, 0);
    IERC20Upgradeable(lpToken0).safeApprove(dystRouter, 0);
    IERC20Upgradeable(lpToken1).safeApprove(dystRouter, 0);
  }

  function _solidlyToRoute(ISolidlyRouter.Routes[] memory _route) internal pure returns (address[] memory) {
    address[] memory route = new address[](_route.length + 1);
    route[0] = _route[0].from;
    for (uint256 i; i < _route.length; ++i) {
      route[i + 1] = _route[i].to;
    }
    return route;
  }

  function outputToNative() external view returns (address[] memory) {
    ISolidlyRouter.Routes[] memory _route = outputToNativeRoute;
    return _solidlyToRoute(_route);
  }

  function outputToLp0() external view returns (address[] memory) {
    ISolidlyRouter.Routes[] memory _route = outputToLp0Route;
    return _solidlyToRoute(_route);
  }

  function outputToLp1() external view returns (address[] memory) {
    ISolidlyRouter.Routes[] memory _route = outputToLp1Route;
    return _solidlyToRoute(_route);
  }
}

