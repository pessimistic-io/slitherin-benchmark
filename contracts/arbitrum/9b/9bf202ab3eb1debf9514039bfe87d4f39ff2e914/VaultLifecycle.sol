// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {SafeMath} from "./SafeMath.sol";
import {IERC20} from "./ERC20_IERC20.sol";
import {Vault} from "./Vault.sol";
import {ShareMath} from "./ShareMath.sol";

import {IERC20Detailed} from "./IERC20Detailed.sol";
import {SafeERC20} from "./SafeERC20.sol";

import "./console.sol";

/**
 * @dev copied from Ribbon's VaultLifeCycle, changed to internal library for gas optimization
 */
library VaultLifecycle {
  using SafeMath for uint;
  using SafeERC20 for IERC20;

  /**
   * @notice Calculate the shares to mint, new price per share,
   *         and amount of funds to re-allocate as collateral for the new round
   * @param currentShareSupply is the total supply of shares
   * @param asset is the address of the vault's asset
   * @param decimals is the decimals of the asset
   * @param pendingAmount is the amount of funds pending from recent deposits
   * @return newLockedAmount is the amount of funds to allocate for the new round
   * @return queuedWithdrawAmount is the amount of funds set aside for withdrawal
   * @return newPricePerShare is the price per share of the new round
   * @return mintShares is the amount of shares to mint from deposits
   */
  function rollover(
    uint currentShareSupply,
    address asset,
    uint decimals,
    uint pendingAmount,
    uint queuedWithdrawShares
  )
    internal
    view
    returns (
      uint newLockedAmount,
      uint queuedWithdrawAmount,
      uint newPricePerShare,
      uint mintShares
    )
  {
    uint currentBalance = IERC20(asset).balanceOf(address(this));
    console.log("LC currentShareSupply=%s/100  currentBalance=%s/100  pendingAmount=%s/100",
        currentShareSupply/10**16,currentBalance/10**16,pendingAmount/10**16);

    newPricePerShare = ShareMath.pricePerShare(currentShareSupply, currentBalance, pendingAmount, decimals);
    console.log("newPricePerShare=%s/100",newPricePerShare/10**16);

    // After closing the short, if the options expire in-the-money
    // vault pricePerShare would go down because vault's asset balance decreased.
    // This ensures that the newly-minted shares do not take on the loss.
    uint _mintShares = ShareMath.assetToShares(pendingAmount, newPricePerShare, decimals);

    uint newSupply = currentShareSupply.add(_mintShares);

    uint queuedWithdraw = newSupply > 0 ? ShareMath.sharesToAsset(queuedWithdrawShares, newPricePerShare, decimals) : 0;

    return (currentBalance.sub(queuedWithdraw), queuedWithdraw, newPricePerShare, _mintShares);
  }
}

