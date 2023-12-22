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

    self.refundee = payable(msg.sender);

    self.status = GMXTypes.Status.Emergency_Shutdown;

    GMXTypes.RemoveLiquidityParams memory _rlp;
    // Remove all of the vault's LP tokens
    _rlp.lpAmt = self.lpToken.balanceOf(address(this));
    _rlp.executionFee = msg.value;

    GMXManager.removeLiquidity(
      self,
      _rlp
    );

    emit EmergencyShutdown(msg.sender);

    self.status = GMXTypes.Status.Closed;
  }

  /**
    * @dev Emergency repay of vault's debt
    * @param self Vault store data.
    * @param shareRatio Amount of debt to pay proportionate to vault's total supply of shares in 1e18; i.e. 100% = 1e18
  */
  function emergencyRepay(
    GMXTypes.Store storage self,
    uint256 shareRatio
  ) external {
    GMXChecks.beforeEmergencyRepayChecks(self, shareRatio);

    // Repay all borrowed assets; 1e18 == 100% shareRatio to repay
    GMXTypes.RepayParams memory _rp;
    (
      _rp.repayTokenAAmt,
      _rp.repayTokenBAmt
    ) = GMXManager.calcRepay(self, shareRatio);

    (
      bool _swapNeeded,
      address _tokenFrom,
      address _tokenTo,
      uint256 _tokenFromAmt
    ) = GMXManager.calcSwapForRepay(self, _rp);

    if (_swapNeeded) {
      GMXTypes.SwapParams memory _sp;
      _sp.tokenIn = _tokenFrom;
      _sp.tokenOut = _tokenTo;
      _sp.amountIn = _tokenFromAmt;
      _sp.slippage = 0;
      _sp.deadline = block.timestamp;

      GMXManager.swap(self, _sp);
    }

    GMXManager.repay(
      self,
      _rp.repayTokenAAmt,
      _rp.repayTokenBAmt
    );
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

    self.refundee = payable(msg.sender);

    GMXTypes.AddLiquidityParams memory _alp;
    _alp.tokenAAmt = self.tokenA.balanceOf(address(this));
    _alp.tokenBAmt = self.tokenB.balanceOf(address(this));
    _alp.executionFee = msg.value;

    GMXManager.addLiquidity(
      self,
      _alp
    );

    emit EmergencyResume(msg.sender);

    self.refundee = payable(address(0));

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

