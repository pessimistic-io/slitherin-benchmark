// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { GMXTypes } from "./GMXTypes.sol";
// import { GMXChecks } from "./GMXChecks.sol";
// import { GMXManager } from "./GMXManager.sol";

library GMXEmergency {
  using SafeERC20 for IERC20;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  uint256 public constant DUST_AMOUNT = 1e17;

  /* ========== EVENTS ========== */

  event EmergencyShutdown(address indexed caller);
  event EmergencyResume(address indexed caller);
  event EmergencyWithdraw(
    address indexed user,
    address assetA,
    uint256 assetAAmt,
    address assetB,
    uint256 assetBAmt,
    uint256 sharesAmt
  );

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * @dev Emergency shut down of vault that withdraws all assets and repays all debt
    * @param self Vault store data
    * @param slippage Slippage tolerance for minimum amount to receive; e.g. 3 = 0.03%
    * @param deadline Timestamp of deadline for swap to go through
  */
  function emergencyShutdown(
    GMXTypes.Store storage self,
    uint256 slippage,
    uint256 deadline
  ) external {
    // GMXManager.emergencyShutdown(self, slippage, deadline);

    // emit EmergencyShutdown(msg.sender);
  }

  /**
    * @dev Emergency resumuption of vault that re-deposits all assets,
    * and unpauses deposits and normal withdrawals
    * @notice Calling this function assumes that there will be enough lending liquidity
    * to match the strategy's leverage and current value of assets in the vault.
    * If there is not enough lending liquidity, we should not resume the strategy vault.
    * @param self Vault store data
    * @param slippage Slippage tolerance for minimum amount to receive; e.g. 3 = 0.03%
    * @param deadline Timestamp of deadline for swap to go through
  */
  function emergencyResume(
    GMXTypes.Store storage self,
    uint256 slippage,
    uint256 deadline
  ) external {
    // GMXManager.emergencyResume(self, slippage, deadline);

    // emit EmergencyResume(msg.sender);
  }

  /**
    * @dev Emergency withdraw function, enabled only when vault is paused,
    * burns svToken from user and withdraws tokenA and tokenB to user
    * @param self Vault store data
    * @param wc WithdrawCache struct
  */
  function emergencyWithdraw(
    GMXTypes.Store storage self,
    GMXTypes.WithdrawCache memory wc
  ) external {
    // // check to ensure shares withdrawn does not exceed user's balance
    // uint256 _userShareBalance = IERC20(address(self.vault)).balanceOf(msg.sender);

    // // user will receive both tokenA and tokenB
    // // but user/front-end should just pass in one of the whitelisted here for checks
    // GMXChecks.beforeWithdrawChecks(self, withdrawParams);

    // // to avoid leaving dust behind
    // unchecked {
    //   if (_userShareBalance - withdrawParams.shareAmt < DUST_AMOUNT) {
    //     withdrawParams.shareAmt = _userShareBalance;
    //   }
    // }

    // // share ratio calculation must be before burn()
    // uint256 _shareRatio = withdrawParams.shareAmt * SAFE_MULTIPLIER
    //                       / IERC20(address(self.vault)).totalSupply();

    // self.vault.burn(msg.sender, withdrawParams.shareAmt);

    // uint256 _withdrawAmtTokenA = _shareRatio
    //                              * self.tokenA.balanceOf(address(this))
    //                              / SAFE_MULTIPLIER;
    // uint256 _withdrawAmtTokenB = _shareRatio
    //                              * self.tokenB.balanceOf(address(this))
    //                              / SAFE_MULTIPLIER;

    // self.tokenA.safeTransfer(msg.sender, _withdrawAmtTokenA);
    // self.tokenB.safeTransfer(msg.sender, _withdrawAmtTokenB);

    // emit EmergencyWithdraw(
    //   msg.sender,
    //   address(self.tokenA),
    //   _withdrawAmtTokenA,
    //   address(self.tokenB),
    //   _withdrawAmtTokenB,
    //   withdrawParams.shareAmt
    // );
  }
}

