// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {PayoutAutomationBaseGelato} from "./PayoutAutomationBaseGelato.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {IPolicyPool} from "./IPolicyPool.sol";
import {IWETH9} from "./IWETH9.sol";
import {IPool} from "./IPool.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {ISwapRouter} from "./ISwapRouter.sol";

contract AAVEBuyEthPayoutAutomation is PayoutAutomationBaseGelato {
  using WadRayMath for uint256;

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
      "AAVEBuyEthPayoutAutomation: you must specify AAVE's Pool address"
    );
    _aave = aave_;
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
    weth.approve(address(_aave), type(uint256).max);
  }

  function _handlePayout(address receiver, uint256 amount) internal override {
    // WARNING: in this contract, different to other payout automations, the amount received is in ETH,
    // since all the USD were already exchanged in the _payTxFee function. This is to avoid doing the exchange twice.
    // "Practicality beats purity"
    address asset = address(weth);
    if (amount != 0) {
      _aave.supply(asset, amount, receiver, 0);
    }
  }

  /**
   * @dev Exchange ALL the payout for ETH, pay gelato for the transaction fee and return the remaining amount
   * @param amount The payout amount that was received
   * @return The remaining amount in ETH after paying the transaction fee
   */
  function _payTxFee(uint256 amount) internal override returns (uint256) {
    (uint256 fee, address feeToken) = _getFeeDetails();
    require(feeToken == ETH, "Unsupported feeToken for gelato payment");

    uint256 ethMin = (amount * _wadToCurrencyFactor).wadDiv(_oracle.getCurrentPrice()).wadMul(
      WAD - _priceTolerance
    );

    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
      tokenIn: address(_policyPool.currency()),
      tokenOut: address(weth),
      fee: _swapParams.feeTier,
      recipient: address(this),
      deadline: block.timestamp,
      amountIn: amount,
      amountOutMinimum: ethMin,
      sqrtPriceLimitX96: 0 // Since we're limiting the transfer amount, we don't need to worry about the price impact of the transaction
    });

    uint256 receivedEth = _swapParams.swapRouter.exactInputSingle(params);

    // Sanity check
    require(
      (receivedEth >= ethMin) && (receivedEth >= fee),
      "AAVEBuyEthPayoutAutomation: the payout is not enough to cover the tx fees"
    );

    // Convert the WMATIC to MATIC for fee payment
    weth.withdraw(fee);
    _transfer(fee, feeToken);

    // WARNING: this returns the remaining amount in ETH, this is different from other payout automations
    // The reason is we already exchanged all the USD for ETH. "Practicality beats purity"
    return receivedEth - fee;
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}

