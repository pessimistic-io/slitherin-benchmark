// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {PayoutAutomationBaseGelato} from "./PayoutAutomationBaseGelato.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {IPolicyPool} from "./IPolicyPool.sol";
import {IWETH9} from "./IWETH9.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {ISwapRouter} from "./ISwapRouter.sol";

contract ForwardPayoutAutomation is PayoutAutomationBaseGelato {
  using SafeERC20 for IERC20Metadata;

  /// @custom:oz-upgrades-unsafe-allow constructor
  // solhint-disable-next-line no-empty-blocks
  constructor(
    IPolicyPool policyPool_,
    address automate_,
    IWETH9 weth_
  ) PayoutAutomationBaseGelato(policyPool_, automate_, weth_) {}

  function initialize(
    string memory name_,
    string memory symbol_,
    address admin,
    IPriceOracle oracle_,
    ISwapRouter swapRouter_,
    uint24 feeTier_
  ) public initializer {
    __PayoutAutomationBaseGelato_init(name_, symbol_, admin, oracle_, swapRouter_, feeTier_);
  }

  function _handlePayout(address receiver, uint256 amount) internal virtual override {
    _policyPool.currency().safeTransfer(receiver, amount);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}

