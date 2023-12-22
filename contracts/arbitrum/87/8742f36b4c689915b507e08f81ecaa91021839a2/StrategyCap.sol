// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

import "./Initializable.sol";
import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./StratManagerUpgradeable.sol";
import "./DynamicFeeManager.sol";
import "./StringUtils.sol";

import "./ICapPool.sol";
import "./ICapRewards.sol";
import "./IArbUSDCToken.sol";

contract StrategyCap is Initializable, StratManagerUpgradeable, DynamicFeeManager {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  // Tokens used
  address public native;
  address public output;
  address public want;

  // Third party contracts
  address public chef;
  address public rewarder;

  bool public harvestOnDeposit;
  uint256 public lastHarvest;
  uint256 public coolDown;

  event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
  event Deposit(uint256 tvl);
  event Withdraw(uint256 tvl);

  // Dynamic Fee functionality
  uint256 public feeOnProfits;

  function __StrategyCap_init(
    address _want,
    address _chef,
    address _vault,
    address _unirouter,
    address _keeper,
    address _strategist,
    address _feeRecipient,
    address _output,
    address _native,
    address _rewarder,
    uint256 _coolDown
  ) public initializer {
    __Ownable_init_unchained();
    __Pausable_init_unchained();
    __StratManager_init_unchained(_keeper, _strategist, _unirouter, _vault, _feeRecipient);
    __DynamicFeeManager_init_unchained();
    __StrategyCap_init_unchained(_want, _chef, _output, _native, _rewarder, _coolDown);
  }

  function __StrategyCap_init_unchained(
    address _want,
    address _chef,
    address _output,
    address _native,
    address _rewarder,
    uint256 _coolDown
  ) internal initializer {
    harvestOnDeposit = false;
    feeOnProfits = 40;

    want = _want;
    chef = _chef;
    output = _output;
    native = _native;
    rewarder = _rewarder;
    coolDown = _coolDown;
    _giveAllowances();
  }

  // puts the funds to work
  function deposit() public whenNotPaused {
    uint256 wantBal = balanceOfWantCap();

    if (wantBal > 0 && canDepositToCap()) {
      ICapPool(chef).deposit(wantBal);
      emit Deposit(balanceOf());
    }
  }

  function withdraw(uint256 _amount) external {
    require(msg.sender == vault, "!vault");
    require(canWithdrawFromCap(), "!cooldown");

    uint256 wantBal = (IERC20Upgradeable(want).balanceOf(address(this)) * ICapPool(chef).UNIT()) /
      (10**IArbUSDCToken(want).decimals());

    _amount = (_amount * ICapPool(chef).UNIT()) / (10**IArbUSDCToken(want).decimals());

    if (wantBal < _amount) {
      ICapPool(chef).withdraw(_amount - wantBal);
      wantBal = IERC20Upgradeable(want).balanceOf(address(this));
    }

    if (wantBal > _amount) {
      wantBal = _amount;
      wantBal = ((wantBal * (10**IArbUSDCToken(want).decimals())) / ICapPool(chef).UNIT());
    }

    if (tx.origin != owner() && !paused()) {
      uint256 withdrawalFeeAmount = (wantBal * withdrawalFee) / WITHDRAWAL_MAX;
      wantBal = wantBal - withdrawalFeeAmount;
    }

    IERC20Upgradeable(want).safeTransfer(vault, wantBal);
    emit Withdraw(balanceOf());
  }

  function beforeDeposit() external override {
    if (harvestOnDeposit && canDepositToCap()) {
      require(msg.sender == vault, "!vault");
      _harvest(tx.origin);
    }
  }

  function harvest() external virtual {
    require(canDepositToCap(), "!cooldown");
    _harvest(tx.origin);
  }

  function harvest(address callFeeRecipient) external virtual {
    require(canDepositToCap(), "!cooldown");
    _harvest(callFeeRecipient);
  }

  function managerHarvest() external onlyManager {
    require(canDepositToCap(), "!cooldown");
    _harvest(tx.origin);
  }

  // compounds earnings and charges performance fee
  function _harvest(address callFeeRecipient) internal whenNotPaused {
    deposit();
    ICapRewards(rewarder).collectReward();
    uint256 outputBal = IERC20Upgradeable(output).balanceOf(address(this));
    if (outputBal > 0) {
      chargeFees(callFeeRecipient);
      uint256 wantHarvested = balanceOfWant();
      deposit();

      lastHarvest = block.timestamp;
      emit StratHarvest(msg.sender, wantHarvested, balanceOf());
    }
  }

  function outputBalance() public view returns (uint256) {
    return IERC20Upgradeable(output).balanceOf(address(this));
  }

  function canDepositToCap() public view returns (bool) {
    return (ICapPool(chef).minDepositTime() + lastHarvest + coolDown) < block.timestamp;
  }

  function canWithdrawFromCap() public view returns (bool) {
    return (ICapPool(chef).minDepositTime() + lastHarvest) < block.timestamp;
  }

  function nativeTokenBalance() public view returns (uint256) {
    return IERC20Upgradeable(native).balanceOf(address(this));
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

  function recoverFunds(address _tokenAddress, uint256 amount) public onlyManager {
    IERC20Upgradeable(_tokenAddress).safeTransfer(msg.sender, amount);
  }

  function recoverAllFunds(address _tokenAddress) public onlyManager {
    IERC20Upgradeable(_tokenAddress).safeTransfer(
      msg.sender,
      IERC20Upgradeable(_tokenAddress).balanceOf(address(this))
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

  // it calculates how much 'want' this contract holds.
  function balanceOfWantCap() public view returns (uint256) {
    return
      (IERC20Upgradeable(want).balanceOf(address(this)) * ICapPool(chef).UNIT()) / (10**IArbUSDCToken(want).decimals());
  }

  // it calculates how much 'want' the strategy has working in the farm.
  function balanceOfPool() public view returns (uint256) {
    return
      (ICapPool(chef).getCurrencyBalance(address(this)) / ICapPool(chef).UNIT()) * (10**IArbUSDCToken(want).decimals());
  }

  function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
    harvestOnDeposit = _harvestOnDeposit;

    if (harvestOnDeposit) {
      setWithdrawalFee(0);
    } else {
      setWithdrawalFee(10);
    }
  }

  // pauses deposits and withdraws all funds from third party systems.
  function panic() public onlyManager {
    pause();
    ICapPool(chef).withdraw(balanceOfPool());
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
    IERC20Upgradeable(want).safeApprove(chef, type(uint256).max);
  }

  function _removeAllowances() internal {
    IERC20Upgradeable(want).safeApprove(chef, 0);
  }

  // Setter for Dynamic fee percentage
  function setFeeOnProfits(uint256 _feeOnProfits) external onlyManager {
    require(_feeOnProfits <= 100, "Dynamic Fees can be set to maximum of 10% (100)");
    feeOnProfits = _feeOnProfits;
  }

  /**
   * @dev Updates value of the additional cooldown.
   * @param _coolDown new vault value.
   */
  function setCoolDown(uint256 _coolDown) external onlyManager {
    coolDown = _coolDown;
  }

  receive() external payable {}
}

