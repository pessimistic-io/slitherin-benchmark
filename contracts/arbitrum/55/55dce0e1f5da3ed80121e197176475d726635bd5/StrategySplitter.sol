// SPDX-License-Identifier: ISC
/**
 * By using this software, you understand, acknowledge and accept that Tetu
 * and/or the underlying software are provided “as is” and “as available”
 * basis and without warranties or representations of any kind either expressed
 * or implied. Any use of this open source software released under the ISC
 * Internet Systems Consortium license is done at your own risk to the fullest
 * extent permissible pursuant to applicable law any and all liability as well
 * as all warranties, including any fitness for a particular purpose with respect
 * to Tetu and/or the underlying software and the use thereof are disclaimed.
 */
pragma solidity ^0.8.9;

import "./SafeERC20.sol";
import "./Math.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./Controllable.sol";
import "./IStrategySplitter.sol";
import "./IStrategy.sol";
import "./ArrayLib.sol";
/// @title Proxy solution for connection a vault with multiple strategies
/// @dev Should be used with TetuProxyControlled.sol
/// @author belbix
contract StrategySplitter is IStrategySplitter, Initializable, OwnableUpgradeable {
  using SafeERC20 for IERC20;
  using ArrayLib for address[];

  // ************ VARIABLES **********************
  uint internal constant _PRECISION = 1e18;
  uint public constant STRATEGY_RATIO_DENOMINATOR = 100;
  uint public constant WITHDRAW_REQUEST_TIMEOUT = 1 hours;
  uint internal constant _MIN_OP = 1;

  // user accounts
  address public controller;

  address[] public strategies;
  address public underlying;
  address public vault;
  uint public needRebalance;
  uint public wantToWithdraw;
  bool public onPause;
  mapping(address => uint) public override strategiesRatios;
  mapping(address => uint) public override withdrawRequestsCalls;

  // ***************** EVENTS ********************
  event StrategyAdded(address strategy);
  event StrategyRemoved(address strategy);
  event StrategyRatioChanged(address strategy, uint ratio);
  event RequestWithdraw(address user, uint amount, uint time);
  event Salvage(address recipient, address token, uint256 amount);
  event RebalanceAll(uint underlyingBalance, uint strategiesBalancesSum);
  event Rebalance(address strategy);

  /// @notice Initialize contract after setup it as proxy implementation
  /// @dev Use it only once after first logic setup
  ///      Initialize Controllable with sender address
  function initialize(address _controller, address _underlying, address __vault) external initializer {
    controller = _controller;
    underlying = _underlying;
    vault = __vault;

    __Ownable_init();
  }

  modifier restricted() {
    require(msg.sender == vault, "!vault");
    _;
  }

  modifier onlyController() {
    require(msg.sender == controller, "!controller");
    _;
  }

  modifier onlyControllerAndVault() {
    require(msg.sender == controller || msg.sender == vault, "!controller");
    _;
  }

  function addStrategy(address _strategy) external override onlyController {
    require(IStrategy(_strategy).underlying() == underlying, "Wrong underlying");
    strategies.addUnique(_strategy);
    emit StrategyAdded(_strategy);
  }

  /// @dev Remove given strategy, reset the ratio and withdraw all underlying to this contract
  function removeStrategy(address _strategy) external override onlyController {
    require(strategies.length > 1, "Can't remove last strategy");
    strategies.findAndRemove(_strategy, true);
    uint ratio = strategiesRatios[_strategy];
    strategiesRatios[_strategy] = 0;
    if (ratio != 0) {
      address strategyWithHighestRatio = strategies[0];
      strategiesRatios[strategyWithHighestRatio] = ratio + strategiesRatios[strategyWithHighestRatio];
      strategies.sortAddressesByUintReverted(strategiesRatios);
    }
    IERC20(underlying).safeApprove(_strategy, 0);
    // for expensive strategies should be called before removing
    IStrategy(_strategy).withdrawAll(address(this));
    transferAllUnderlyingToVault();
    emit StrategyRemoved(_strategy);
  }

  function setStrategyRatios(address[] memory _strategies, uint[] memory _ratios) external override onlyOwner {
    require(_strategies.length == strategies.length, "Wrong input strategies");
    require(_strategies.length == _ratios.length, "Wrong input arrays");
    uint sum;
    for (uint i; i < _strategies.length; i++) {
      bool exist = false;
      for (uint j; j < strategies.length; j++) {
        if (strategies[j] == _strategies[i]) {
          exist = true;
          break;
        }
      }
      require(exist, "Strategy not exist");
      sum += _ratios[i];
      strategiesRatios[_strategies[i]] = _ratios[i];
      emit StrategyRatioChanged(_strategies[i], _ratios[i]);
    }
    require(sum == STRATEGY_RATIO_DENOMINATOR, "Wrong sum");

    // sorting strategies by ratios
    strategies.sortAddressesByUintReverted(strategiesRatios);
  }

  function strategiesInited() external view override returns (bool) {
    uint sum;
    for (uint i; i < strategies.length; i++) {
      sum += strategiesRatios[strategies[i]];
    }
    return sum == STRATEGY_RATIO_DENOMINATOR;
  }

  /// @dev Try to withdraw all from all strategies. May be too expensive to handle in one tx
  function withdrawAllToVault() external override onlyController {
    for (uint i = 0; i < strategies.length; i++) {
      IStrategy(strategies[i]).withdrawAll(address(this));
    }
    transferAllUnderlyingToVault();
  }

  function emergencyExit() external override restricted {
    transferAllUnderlyingToVault();
    onPause = true;
  }

  /// @dev Cascade withdraw from strategies start from with higher ratio until reach the target amount.
  ///      For large amounts with multiple strategies may not be possible to process this function.
  function withdrawToVault(uint256 amount) external override onlyControllerAndVault {
    uint uBalance = IERC20(underlying).balanceOf(address(this));
    if (uBalance < amount) {
      for (uint i; i < strategies.length; i++) {
        IStrategy strategy = IStrategy(strategies[i]);
        uint strategyBalance = strategy.investedUnderlyingBalance();
        if (strategyBalance <= amount) {
          strategy.withdrawAll(address(this));
        } else {
          if (amount > _MIN_OP) {
            strategy.withdraw(address(this), amount);
          }
        }
        uBalance = IERC20(underlying).balanceOf(address(this));
        if (uBalance >= amount) {
          break;
        }
      }
    }
    transferAllUnderlyingToVault();
  }

  function doHardWork() external override {
    for (uint i = 0; i < strategies.length; i++) {
      IStrategy(strategies[i]).earn();
    }
  }

  function investAllUnderlying() external {
    rebalanceAll();
  }

  function rebalanceAll() public {
    require(msg.sender == controller || msg.sender == vault, "Forbidden");
    require(!onPause, "SS: Paused");
    needRebalance = 0;
    // collect balances sum
    uint _underlyingBalance = IERC20(underlying).balanceOf(address(this));
    uint _strategiesBalancesSum = _underlyingBalance;
    for (uint i = 0; i < strategies.length; i++) {
      _strategiesBalancesSum += IStrategy(strategies[i]).investedUnderlyingBalance();
    }
    if (_strategiesBalancesSum == 0) {
      return;
    }
    // rebalance only strategies requires withdraw
    // it will move necessary amount to this contract
    for (uint i = 0; i < strategies.length; i++) {
      uint _ratio = strategiesRatios[strategies[i]] * _PRECISION;
      if (_ratio == 0) {
        continue;
      }
      uint _strategyBalance = IStrategy(strategies[i]).investedUnderlyingBalance();
      uint _currentRatio = (_strategyBalance * _PRECISION * STRATEGY_RATIO_DENOMINATOR) / _strategiesBalancesSum;
      if (_currentRatio > _ratio) {
        // not necessary update underlying balance for withdraw
        _rebalanceCall(strategies[i], _strategiesBalancesSum, _strategyBalance, _ratio);
      }
    }

    // rebalance only strategies requires deposit
    for (uint i = 0; i < strategies.length; i++) {
      uint _ratio = strategiesRatios[strategies[i]] * _PRECISION;
      if (_ratio == 0) {
        continue;
      }
      uint _strategyBalance = IStrategy(strategies[i]).investedUnderlyingBalance();
      uint _currentRatio = (_strategyBalance * _PRECISION * STRATEGY_RATIO_DENOMINATOR) / _strategiesBalancesSum;
      if (_currentRatio < _ratio) {
        _rebalanceCall(strategies[i], _strategiesBalancesSum, _strategyBalance, _ratio);
      }
    }
    emit RebalanceAll(_underlyingBalance, _strategiesBalancesSum);
  }

  /// @dev External function for calling rebalance for exact strategy
  ///      Strategies that need withdraw action should be called first
  function rebalance(address _strategy) external onlyController {
    require(!onPause, "SS: Paused");
    needRebalance = 0;
    _rebalance(_strategy);
    emit Rebalance(_strategy);
  }

  /// @dev Deposit or withdraw from given strategy according the strategy ratio
  ///      Should be called from EAO with multiple off-chain steps
  function _rebalance(address _strategy) internal {
    // normalize ratio to 18 decimals
    uint _ratio = strategiesRatios[_strategy] * _PRECISION;
    // in case of unknown strategy will be reverted here
    require(_ratio != 0, "SS: Zero ratio strategy");
    uint _strategyBalance;
    uint _strategiesBalancesSum = IERC20(underlying).balanceOf(address(this));
    // collect strategies balances sum with some tricks for gas optimisation
    for (uint i = 0; i < strategies.length; i++) {
      uint balance = IStrategy(strategies[i]).investedUnderlyingBalance();
      if (strategies[i] == _strategy) {
        _strategyBalance = balance;
      }
      _strategiesBalancesSum += balance;
    }

    _rebalanceCall(_strategy, _strategiesBalancesSum, _strategyBalance, _ratio);
  }

  ///@dev Deposit or withdraw from strategy
  function _rebalanceCall(address _strategy, uint _strategiesBalancesSum, uint _strategyBalance, uint _ratio) internal {
    uint _currentRatio = (_strategyBalance * _PRECISION * STRATEGY_RATIO_DENOMINATOR) / _strategiesBalancesSum;
    if (_currentRatio < _ratio) {
      // Need to deposit to the strategy.
      // We are calling investAllUnderlying() because we anyway will spend similar gas
      // in case of withdraw, and we can't predict what will need.
      uint needToDeposit = (_strategiesBalancesSum * (_ratio - _currentRatio)) /
        (STRATEGY_RATIO_DENOMINATOR * _PRECISION);
      uint _underlyingBalance = IERC20(underlying).balanceOf(address(this));
      needToDeposit = Math.min(needToDeposit, _underlyingBalance);
      //      require(_underlyingBalance >= needToDeposit, "SS: Not enough splitter balance");
      if (needToDeposit > _MIN_OP) {
        IERC20(underlying).safeTransfer(_strategy, needToDeposit);
        IStrategy(_strategy).investAllUnderlying();
      }
    } else if (_currentRatio > _ratio) {
      // withdraw from strategy excess value
      uint needToWithdraw = (_strategiesBalancesSum * (_currentRatio - _ratio)) /
        (STRATEGY_RATIO_DENOMINATOR * _PRECISION);
      needToWithdraw = Math.min(needToWithdraw, _strategyBalance);
      //      require(_strategyBalance >= needToWithdraw, "SS: Not enough strat balance");
      if (needToWithdraw > _MIN_OP) {
        IStrategy(_strategy).withdrawToVault(needToWithdraw);
      }
    }
  }

  /// @dev Change rebalance marker
  function setNeedRebalance(uint _value) external onlyController {
    require(_value < 2, "SS: Wrong value");
    needRebalance = _value;
  }

  /// @dev Stop deposit to strategies
  function pauseInvesting() external override restricted {
    onPause = true;
  }

  /// @dev Continue deposit to strategies
  function continueInvesting() external override restricted {
    onPause = false;
  }

  function transferAllUnderlyingToVault() internal {
    uint balance = IERC20(underlying).balanceOf(address(this));
    if (balance > 0) {
      IERC20(underlying).safeTransfer(vault, balance);
    }
  }

  // **************** VIEWS ***************

  /// @dev Return array of reward tokens collected across all strategies.
  ///      Has random sorting
  function strategyRewardTokens() external view override returns (address[] memory) {
    return _strategyRewardTokens();
  }

  function _strategyRewardTokens() internal view returns (address[] memory) {
    address[] memory rts = new address[](20);
    uint size = 0;
    for (uint i = 0; i < strategies.length; i++) {
      address[] memory strategyRts;
      if (IStrategy(strategies[i]).platform() == IStrategy.Platform.STRATEGY_SPLITTER) {
        strategyRts = IStrategySplitter(strategies[i]).strategyRewardTokens();
      } else {
        strategyRts = IStrategy(strategies[i]).rewardTokens();
      }
      for (uint j = 0; j < strategyRts.length; j++) {
        address rt = strategyRts[j];
        bool exist = false;
        for (uint k = 0; k < rts.length; k++) {
          if (rts[k] == rt) {
            exist = true;
            break;
          }
        }
        if (!exist) {
          rts[size] = rt;
          size++;
        }
      }
    }
    address[] memory result = new address[](size);
    for (uint i = 0; i < size; i++) {
      result[i] = rts[i];
    }
    return result;
  }

  /// @dev Splitter underlying balance
  function underlyingBalance() external view override returns (uint256) {
    return IERC20(underlying).balanceOf(address(this));
  }

  /// @dev Return strategies balances. Doesn't include splitter underlying balance
  function rewardPoolBalance() external view override returns (uint256) {
    uint balance;
    for (uint i = 0; i < strategies.length; i++) {
      balance += IStrategy(strategies[i]).investedUnderlyingBalance();
    }
    return balance;
  }

  /// @dev Return average buyback ratio
  function buyBackRatio() external view override returns (uint256) {
    uint bbRatio = 0;
    for (uint i = 0; i < strategies.length; i++) {
      bbRatio += IStrategy(strategies[i]).buyBackRatio();
    }
    bbRatio = bbRatio / strategies.length;
    return bbRatio;
  }

  /// @dev Check unsalvageable tokens across all strategies
  function unsalvageableTokens(address token) external view override returns (bool) {
    for (uint i = 0; i < strategies.length; i++) {
      if (IStrategy(strategies[i]).unsalvageableTokens(token)) {
        return true;
      }
    }
    return false;
  }

  /// @dev Return a sum of all balances under control. Should be accurate - it will be used in the vault
  function investedUnderlyingBalance() external view override returns (uint256) {
    return _investedUnderlyingBalance();
  }

  function _investedUnderlyingBalance() internal view returns (uint256) {
    uint balance = IERC20(underlying).balanceOf(address(this));
    for (uint i = 0; i < strategies.length; i++) {
      balance += IStrategy(strategies[i]).investedUnderlyingBalance();
    }
    return balance;
  }

  /// @dev Splitter has specific hardcoded platform
  function platform() external pure returns (Platform) {
    return Platform.STRATEGY_SPLITTER;
  }

  /// @dev Assume that we will use this contract only for single token vaults
  function assets() external view override returns (address[] memory) {
    address[] memory result = new address[](1);
    result[0] = underlying;
    return result;
  }

  /// @dev Return ready to claim rewards array
  function readyToClaim() external view override returns (uint256[] memory) {
    uint[] memory rewards = new uint[](20);
    address[] memory rts = new address[](20);
    uint size = 0;
    for (uint i = 0; i < strategies.length; i++) {
      address[] memory strategyRts;
      if (IStrategy(strategies[i]).platform() == IStrategy.Platform.STRATEGY_SPLITTER) {
        strategyRts = IStrategySplitter(strategies[i]).strategyRewardTokens();
      } else {
        strategyRts = IStrategy(strategies[i]).rewardTokens();
      }

      uint[] memory strategyReadyToClaim = IStrategy(strategies[i]).readyToClaim();
      // don't count, better to skip than ruin
      if (strategyRts.length != strategyReadyToClaim.length) {
        continue;
      }
      for (uint j = 0; j < strategyRts.length; j++) {
        address rt = strategyRts[j];
        bool exist = false;
        for (uint k = 0; k < rts.length; k++) {
          if (rts[k] == rt) {
            exist = true;
            rewards[k] += strategyReadyToClaim[j];
            break;
          }
        }
        if (!exist) {
          rts[size] = rt;
          rewards[size] = strategyReadyToClaim[j];
          size++;
        }
      }
    }
    uint[] memory result = new uint[](size);
    for (uint i = 0; i < size; i++) {
      result[i] = rewards[i];
    }
    return result;
  }

  /// @dev Return sum of strategies poolTotalAmount values
  function poolTotalAmount() external view override returns (uint256) {
    uint balance = 0;
    for (uint i = 0; i < strategies.length; i++) {
      balance += IStrategy(strategies[i]).poolTotalAmount();
    }
    return balance;
  }

  /// @dev Return maximum available balance to withdraw without calling more than 1 strategy
  function maxCheapWithdraw() external view override returns (uint) {
    uint strategyBalance;
    if (strategies.length != 0) {
      if (IStrategy(strategies[0]).platform() == IStrategy.Platform.STRATEGY_SPLITTER) {
        strategyBalance = IStrategySplitter(strategies[0]).maxCheapWithdraw();
      } else {
        strategyBalance = IStrategy(strategies[0]).investedUnderlyingBalance();
      }
    }
    return strategyBalance + IERC20(underlying).balanceOf(address(this)) + IERC20(underlying).balanceOf(vault);
  }

  /// @dev Length of strategy array
  function strategiesLength() external view override returns (uint) {
    return strategies.length;
  }

  /// @dev Returns strategy array
  function allStrategies() external view override returns (address[] memory) {
    return strategies;
  }

  /// @dev Simulate vault behaviour - returns vault total supply
  function totalSupply() external view returns (uint256) {
    return IERC20(vault).totalSupply();
  }

  function createdBlock() external view returns (uint256) {}
}

