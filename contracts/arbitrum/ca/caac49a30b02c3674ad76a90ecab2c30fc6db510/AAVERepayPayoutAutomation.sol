// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {PayoutAutomationBaseGelato} from "./PayoutAutomationBaseGelato.sol";
import {Math} from "./Math.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {IPolicyPool} from "./IPolicyPool.sol";
import {IWETH9} from "./IWETH9.sol";
import {IPool} from "./IPool.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {DataTypes} from "./DataTypes.sol";
import {ISwapRouter} from "./ISwapRouter.sol";

contract AAVERepayPayoutAutomation is PayoutAutomationBaseGelato {
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IPool internal immutable _aave;

  /// @custom:oz-upgrades-unsafe-allow constructor
  // solhint-disable-next-line no-empty-blocks
  constructor(
    IPolicyPool policyPool_,
    address automate_,
    IWETH9 weth_,
    IPool aave_
  ) PayoutAutomationBaseGelato(policyPool_, automate_, weth_) {
    require(
      address(aave_) != address(0),
      "AAVERepayPayoutAutomation: you must specify AAVE's Pool address"
    );
    _aave = aave_;
    require(
      aave_.getReserveData(address(policyPool_.currency())).variableDebtTokenAddress != address(0),
      "AAVERepayPayoutAutomation: the protocol currency isn't supported in AAVE"
    );
  }

  function initialize(
    string memory name_,
    string memory symbol_,
    address admin,
    IPriceOracle oracle_,
    ISwapRouter swapRouter_,
    uint24 feeTier_
  ) public virtual initializer {
    __PayoutAutomationBaseGelato_init(name_, symbol_, admin, oracle_, swapRouter_, feeTier_);
    // Infinite approval to AAVE to avoid approving every time
    _policyPool.currency().approve(address(_aave), type(uint256).max);
  }

  function _handlePayout(address receiver, uint256 amount) internal override {
    address asset = address(_policyPool.currency());
    DataTypes.ReserveData memory reserveData = _aave.getReserveData(asset);
    uint256 debt = IERC20Metadata(reserveData.variableDebtTokenAddress).balanceOf(receiver);
    if (debt > 0) {
      amount -= _aave.repay(asset, Math.min(debt, amount), 2, receiver);
    }
    if (amount != 0) {
      debt = IERC20Metadata(reserveData.stableDebtTokenAddress).balanceOf(receiver);
      if (debt > 0) {
        amount -= _aave.repay(asset, Math.min(debt, amount), 1, receiver);
      }
    }
    if (amount != 0) {
      _aave.supply(asset, amount, receiver, 0);
    }
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}

