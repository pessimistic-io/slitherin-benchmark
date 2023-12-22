// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXChecks } from "./GMXChecks.sol";
import { GMXManager } from "./GMXManager.sol";

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
    uint256 sharesAmt,
    address assetA,
    uint256 assetAAmt,
    address assetB,
    uint256 assetBAmt
  );

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * @dev Emergency shut down of vault that withdraws all assets and repays all debt
    * @param self Vault store data
  */
  function emergencyShutdown(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeEmergencyShutdownChecks(self);

    self.status = GMXTypes.Status.Emergency_Shutdown;

    GMXTypes.WithdrawParams memory _wp;
    _wp.token = address(0); // Note: we don't swap for assets
    _wp.shareAmt = 0;
    _wp.minWithdrawTokenAmt = 0;
    _wp.slippage = 0;
    _wp.deadline = 0;
    _wp.executionFee = msg.value;
    _wp.lpAmtToRemove = self.lpToken.balanceOf(address(this)); // All of the vault's LP token

    GMXTypes.SwapParams memory _sp;
    _wp.swapForRepayParams = _sp;
    _wp.swapForWithdrawParams = _sp;

    bytes32 _withdrawKey = GMXManager.removeLiquidity(
      self,
      _wp
    );

    self.status = GMXTypes.Status.Closed;

    emit EmergencyShutdown(msg.sender);
  }

  /**
    * @dev Emergency resumuption of vault that re-deposits all assets,
    * and unpauses deposits and normal withdrawals
    * @notice Calling this function assumes that there will be enough lending liquidity
    * to match the strategy's leverage and current value of assets in the vault.
    * If there is not enough lending liquidity, we should not resume the strategy vault.
    * @param self Vault store data
  */
  function emergencyResume(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeEmergencyResumeChecks(self);

    GMXTypes.DepositParams memory _dp;
    _dp.slippage = 0;
    _dp.deadline = 0;
    _dp.executionFee = msg.value;

    bytes32 _depositKey = GMXManager.addLiquidity(
      self,
      _dp
    );

    emit EmergencyResume(msg.sender);

    // Note that keeper will manually unpause and toggle status to Open
    // after checking that liquidity has been deposited successfully
  }

  /**
    * @dev Emergency withdraw function, enabled only when vault is paused,
    * burns svToken from user and withdraws tokenA and tokenB to user
    * @param self Vault store data
    * @param shareAmt Amount of shares to burn
  */
  function emergencyWithdraw(
    GMXTypes.Store storage self,
    uint256 shareAmt
  ) external {
    // check to ensure shares withdrawn does not exceed user's balance
    uint256 _userShareBalance = IERC20(address(self.vault)).balanceOf(msg.sender);

    // to avoid leaving dust behind
    unchecked {
      if (_userShareBalance - shareAmt < DUST_AMOUNT) {
        shareAmt = _userShareBalance;
      }
    }

    GMXChecks.beforeEmergencyWithdrawChecks(self, shareAmt);

    // share ratio calculation must be before burn()
    uint256 _shareRatio = shareAmt * SAFE_MULTIPLIER
                          / IERC20(address(self.vault)).totalSupply();

    self.vault.burn(msg.sender, shareAmt);

    uint256 _withdrawAmtTokenA = _shareRatio
                                 * self.tokenA.balanceOf(address(this))
                                 / SAFE_MULTIPLIER;
    uint256 _withdrawAmtTokenB = _shareRatio
                                 * self.tokenB.balanceOf(address(this))
                                 / SAFE_MULTIPLIER;

    self.tokenA.safeTransfer(msg.sender, _withdrawAmtTokenA);
    self.tokenB.safeTransfer(msg.sender, _withdrawAmtTokenB);

    emit EmergencyWithdraw(
      msg.sender,
      shareAmt,
      address(self.tokenA),
      _withdrawAmtTokenA,
      address(self.tokenB),
      _withdrawAmtTokenB
    );
  }
}

