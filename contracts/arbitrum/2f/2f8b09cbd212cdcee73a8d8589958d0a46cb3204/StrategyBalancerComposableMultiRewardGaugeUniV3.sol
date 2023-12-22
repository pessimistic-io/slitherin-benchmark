// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./IUniswapRouterETH.sol";
import "./IBalancerVault.sol";
import "./IRewardsGauge.sol";
import "./IStreamer.sol";
import "./IHelper.sol";
import "./StratManagerUpgradeable.sol";
import "./BalancerActionsLib.sol";
import "./BeefyBalancerStructs.sol";
import "./UniV3Actions.sol";
import "./DynamicFeeManager.sol";
import "./console.sol";

interface IBalancerPool {
  function getPoolId() external view returns (bytes32);
}

interface IMinter {
  function mint(address guage) external;
}

contract StrategyBalancerComposableMultiRewardGaugeUniV3 is StratManagerUpgradeable, DynamicFeeManager {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  // Tokens used
  address public want;
  address public output;
  address public native;

  // Third party contracts
  address public rewardsGauge;

  BeefyBalancerStructs.Input public input;
  BeefyBalancerStructs.BatchSwapStruct[] public nativeToWantRoute;
  BeefyBalancerStructs.BatchSwapStruct[] public outputToNativeRoute;
  address[] public nativeToWantAssets;
  address[] public outputToNativeAssets;

  mapping(address => BeefyBalancerStructs.Reward) public rewards;
  address[] public rewardTokens;

  address public uniswapRouter;

  IBalancerVault.SwapKind public swapKind;
  IBalancerVault.FundManagement public funds;

  bool public harvestOnDeposit;
  uint256 public lastHarvest;
  bool isBeets;
  uint256 public feeOnProfits;

  event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
  event Deposit(uint256 tvl);
  event Withdraw(uint256 tvl);
  event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

  function initialize(
    address _want,
    bool[] calldata _switches,
    BeefyBalancerStructs.BatchSwapStruct[] calldata _nativeToWantRoute,
    BeefyBalancerStructs.BatchSwapStruct[] calldata _outputToNativeRoute,
    address[][] calldata _assets,
    address _rewardsGauge,
    bool _isBeets,
    address[] memory _addresses
  ) public initializer {
    feeOnProfits = 50;
    swapKind = IBalancerVault.SwapKind.GIVEN_IN;
    __Ownable_init_unchained();
    __Pausable_init_unchained();
    __DynamicFeeManager_init();
    __StratManager_init_unchained(_addresses[0], _addresses[1], _addresses[2], _addresses[3], _addresses[4]);
    for (uint i; i < _nativeToWantRoute.length; ) {
      nativeToWantRoute.push(_nativeToWantRoute[i]);
      unchecked {
        ++i;
      }
    }

    for (uint j; j < _outputToNativeRoute.length; ) {
      outputToNativeRoute.push(_outputToNativeRoute[j]);
      unchecked {
        ++j;
      }
    }

    outputToNativeAssets = _assets[0];
    nativeToWantAssets = _assets[1];
    output = outputToNativeAssets[0];
    native = nativeToWantAssets[0];
    isBeets = _isBeets;
    input.input = nativeToWantAssets[nativeToWantAssets.length - 1];
    input.isComposable = _switches[0];
    input.isBeets = _switches[1];

    rewardsGauge = _rewardsGauge;
    uniswapRouter = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    funds = IBalancerVault.FundManagement(address(this), false, payable(address(this)), false);

    want = _want;
    _giveAllowances();
  }

  // puts the funds to work
  function deposit() public whenNotPaused {
    uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));

    if (wantBal > 0) {
      IRewardsGauge(rewardsGauge).deposit(wantBal);
      emit Deposit(balanceOf());
    }
  }

  function withdraw(uint256 _amount) external {
    require(msg.sender == vault, "!vault");

    uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));

    if (wantBal < _amount) {
      IRewardsGauge(rewardsGauge).withdraw(_amount - wantBal);
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

  function beforeDeposit() external override {
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
    if (!isBeets) {
      IMinter minter = IMinter(IRewardsGauge(rewardsGauge).bal_pseudo_minter());
      minter.mint(rewardsGauge);
    } else {
      address helper = address(0x299dcDF14350999496204c141A0c20A29d71AF3E);
      IHelper(helper).claimRewards(rewardsGauge, address(this));
    }

    IRewardsGauge(rewardsGauge).claim_rewards();

    IRewardsGauge(rewardsGauge).claim_rewards(address(this));
    swapRewardsToNative();
    uint256 nativeBal = IERC20Upgradeable(native).balanceOf(address(this));

    if (nativeBal > 0) {
      chargeFees(callFeeRecipient);
      addLiquidity();
      uint256 wantHarvested = balanceOfWant();
      deposit();

      lastHarvest = block.timestamp;
      emit StratHarvest(msg.sender, wantHarvested, balanceOf());
    }
  }

  function swapRewardsToNative() internal {
    uint256 outputBal = IERC20Upgradeable(output).balanceOf(address(this));
    if (outputBal > 0) {
      IBalancerVault.BatchSwapStep[] memory _swaps = BalancerActionsLib.buildSwapStructArray(
        outputToNativeRoute,
        outputBal
      );
      BalancerActionsLib.balancerSwap(dystRouter, swapKind, _swaps, outputToNativeAssets, funds, int256(outputBal));
    }
    // extras
    for (uint i; i < rewardTokens.length; i++) {
      uint bal = IERC20Upgradeable(rewardTokens[i]).balanceOf(address(this));
      if (bal >= rewards[rewardTokens[i]].minAmount) {
        if (rewards[rewardTokens[i]].assets[0] != address(0)) {
          BeefyBalancerStructs.BatchSwapStruct[] memory swapInfo = new BeefyBalancerStructs.BatchSwapStruct[](
            rewards[rewardTokens[i]].assets.length - 1
          );
          for (uint j; j < rewards[rewardTokens[i]].assets.length - 1; ) {
            swapInfo[j] = rewards[rewardTokens[i]].swapInfo[j];
            unchecked {
              ++j;
            }
          }
          IBalancerVault.BatchSwapStep[] memory _swaps = BalancerActionsLib.buildSwapStructArray(swapInfo, bal);
          BalancerActionsLib.balancerSwap(
            dystRouter,
            swapKind,
            _swaps,
            rewards[rewardTokens[i]].assets,
            funds,
            int256(bal)
          );
        } else {
          UniV3Actions.swapV3(uniswapRouter, rewards[rewardTokens[i]].routeToNative, bal);
        }
      }
    }
  }

  // performance fees
  function chargeFees(address callFeeRecipient) internal {
    uint256 generalFeeOnProfits = (IERC20Upgradeable(output).balanceOf(address(this)) * feeOnProfits) / 1000;
    uint256 generalFeeAmount = generalFeeOnProfits;
    uint256 callFeeAmount = (generalFeeAmount * callFee) / MAX_FEE;
    if (callFeeAmount > 0) {
      IERC20Upgradeable(output).safeTransfer(callFeeRecipient, callFeeAmount);
    }

    // Calculating the Fee to be distributed
    uint256 feeAmount1 = (generalFeeAmount * fee1) / MAX_FEE;
    uint256 feeAmount2 = (generalFeeAmount * fee2) / MAX_FEE;
    uint256 strategistFeeAmount = (generalFeeAmount * strategistFee) / MAX_FEE;

    // Transfer fees to recipients
    if (feeAmount1 > 0) {
      IERC20Upgradeable(output).safeTransfer(feeRecipient1, feeAmount1);
    }
    if (feeAmount2 > 0) {
      IERC20Upgradeable(output).safeTransfer(feeRecipient2, feeAmount2);
    }
    if (strategistFeeAmount > 0) {
      IERC20Upgradeable(output).safeTransfer(strategist, strategistFeeAmount);
    }
  }

  // Adds liquidity to AMM and gets more LP tokens.
  function addLiquidity() internal {
    uint256 nativeBal = IERC20Upgradeable(native).balanceOf(address(this));
    if (native != input.input) {
      IBalancerVault.BatchSwapStep[] memory _swaps = BalancerActionsLib.buildSwapStructArray(
        nativeToWantRoute,
        nativeBal
      );
      BalancerActionsLib.balancerSwap(dystRouter, swapKind, _swaps, nativeToWantAssets, funds, int256(nativeBal));
    }

    uint256 inputBal = IERC20Upgradeable(input.input).balanceOf(address(this));
    BalancerActionsLib.balancerJoin(dystRouter, IBalancerPool(want).getPoolId(), input.input, inputBal);
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
    return IRewardsGauge(rewardsGauge).balanceOf(address(this));
  }

  // returns rewards unharvested
  function rewardsAvailable() public view returns (uint256) {
    return IRewardsGauge(rewardsGauge).claimable_reward(address(this), output);
  }

  // native reward amount for calling harvest
  function callReward() public pure returns (uint256) {
    return 0; // multiple swap providers with no easy way to estimate native output.
  }

  function addRewardToken(
    address _token,
    BeefyBalancerStructs.BatchSwapStruct[] memory _swapInfo,
    address[] memory _assets,
    bytes calldata _routeToNative,
    uint _minAmount
  ) external onlyOwner {
    require(_token != want, "!want");
    require(_token != native, "!native");
    if (_assets[0] != address(0)) {
      IERC20Upgradeable(_token).safeApprove(dystRouter, 0);
      IERC20Upgradeable(_token).safeApprove(dystRouter, type(uint).max);
    } else {
      IERC20Upgradeable(_token).safeApprove(uniswapRouter, 0);
      IERC20Upgradeable(_token).safeApprove(uniswapRouter, type(uint).max);
    }

    rewards[_token].assets = _assets;
    rewards[_token].routeToNative = _routeToNative;
    rewards[_token].minAmount = _minAmount;

    for (uint i; i < _swapInfo.length; ) {
      rewards[_token].swapInfo[i].poolId = _swapInfo[i].poolId;
      rewards[_token].swapInfo[i].assetInIndex = _swapInfo[i].assetInIndex;
      rewards[_token].swapInfo[i].assetOutIndex = _swapInfo[i].assetOutIndex;
      unchecked {
        ++i;
      }
    }
    rewardTokens.push(_token);
  }

  function resetRewardTokens() external onlyManager {
    for (uint i; i < rewardTokens.length; ) {
      delete rewards[rewardTokens[i]];
      unchecked {
        ++i;
      }
    }
    delete rewardTokens;
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

    IRewardsGauge(rewardsGauge).withdraw(balanceOfPool());

    uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
    IERC20Upgradeable(want).transfer(vault, wantBal);
  }

  // pauses deposits and withdraws all funds from third party systems.
  function panic() public onlyManager {
    pause();
    IRewardsGauge(rewardsGauge).withdraw(balanceOfPool());
  }

  function pause() public onlyManager {
    _pause();

    _removeAllowances();
  }

  function unpause() external onlyManager {
    _unpause();

    _giveAllowances();

    deposit();
  }

  function _giveAllowances() internal {
    IERC20Upgradeable(want).safeApprove(rewardsGauge, type(uint).max);
    IERC20Upgradeable(output).safeApprove(dystRouter, type(uint).max);
    IERC20Upgradeable(native).safeApprove(dystRouter, type(uint).max);
    if (!input.isComposable) {
      IERC20Upgradeable(input.input).safeApprove(dystRouter, 0);
      IERC20Upgradeable(input.input).safeApprove(dystRouter, type(uint).max);
    }

    if (rewardTokens.length != 0) {
      for (uint i; i < rewardTokens.length; ++i) {
        if (rewards[rewardTokens[i]].assets[0] != address(0)) {
          IERC20Upgradeable(rewardTokens[i]).safeApprove(dystRouter, 0);
          IERC20Upgradeable(rewardTokens[i]).safeApprove(dystRouter, type(uint).max);
        } else {
          IERC20Upgradeable(rewardTokens[i]).safeApprove(uniswapRouter, 0);
          IERC20Upgradeable(rewardTokens[i]).safeApprove(uniswapRouter, type(uint).max);
        }
      }
    }
  }

  function _removeAllowances() internal {
    IERC20Upgradeable(want).safeApprove(rewardsGauge, 0);
    IERC20Upgradeable(output).safeApprove(dystRouter, 0);
    IERC20Upgradeable(native).safeApprove(dystRouter, 0);
    if (!input.isComposable) {
      IERC20Upgradeable(input.input).safeApprove(dystRouter, 0);
    }
    if (rewardTokens.length != 0) {
      for (uint i; i < rewardTokens.length; ++i) {
        if (rewards[rewardTokens[i]].assets[0] != address(0)) {
          IERC20Upgradeable(rewardTokens[i]).safeApprove(dystRouter, 0);
        } else {
          IERC20Upgradeable(rewardTokens[i]).safeApprove(uniswapRouter, 0);
        }
      }
    }
  }
}

