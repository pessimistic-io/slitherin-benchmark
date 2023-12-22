// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { ISwap } from "./ISwap.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXReader } from "./GMXReader.sol";
import { GMXChecks } from "./GMXChecks.sol";
import { GMXManager } from "./GMXManager.sol";

/**
  * @title GMXEmergency
  * @author Steadefi
  * @notice Re-usable library functions for emergency operations for Steadefi leveraged vaults
*/
library GMXEmergency {
  using SafeERC20 for IERC20;

  /* ====================== CONSTANTS ======================== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  uint256 public constant DUST_AMOUNT = 1e17;

  /* ======================== EVENTS ========================= */

  event EmergencyPaused();
  event EmergencyRepaid(
    uint256 repayTokenAAmt,
    uint256 repayTokenBAmt
  );
  event EmergencyBorrowed(
    uint256 borrowTokenAAmt,
    uint256 borrowTokenBAmt
  );
  event EmergencyResumed();
  event EmergencyResumedCancelled();
  event EmergencyClosed();
  event EmergencyWithdraw(
    address indexed user,
    uint256 sharesAmt,
    address assetA,
    uint256 assetAAmt,
    address assetB,
    uint256 assetBAmt
  );

  /* ================== MUTATIVE FUNCTIONS =================== */

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function emergencyPause(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeEmergencyPauseChecks(self);

    if (self.status != GMXTypes.Status.Open) {
      // If vault is processing a tx, set flag to pause after tx is processed
      self.shouldEmergencyPause = true;
    } else {
      self.status = GMXTypes.Status.Paused;

      emit EmergencyPaused();
    }
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function emergencyRepay(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeEmergencyRepayChecks(self);

    self.refundee = payable(msg.sender);

    self.lpAmt -= self.lpToken.balanceOf(address(this));

    GMXTypes.RemoveLiquidityParams memory _rlp;

    // Remove all of the vault's LP tokens
    _rlp.lpAmt = self.lpToken.balanceOf(address(this));
    _rlp.executionFee = msg.value;

    GMXManager.removeLiquidity(
      self,
      _rlp
    );

    self.status = GMXTypes.Status.Repaid;
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function processEmergencyRepay(
    GMXTypes.Store storage self,
    uint256 tokenAReceived,
    uint256 tokenBReceived
  ) external {
    GMXChecks.beforeProcessEmergencyRepayChecks(self);

    // Repay all borrowed assets; 1e18 == 100% shareRatio to repay
    GMXTypes.RepayParams memory _rp;
    (
      _rp.repayTokenAAmt,
      _rp.repayTokenBAmt
    ) = GMXManager.calcRepay(self, 1e18);

    (
      bool _swapNeeded,
      address _tokenFrom,
      address _tokenTo,
      uint256 _tokenToAmt
    ) = GMXManager.calcSwapForRepay(
      self,
      _rp,
      tokenAReceived,
      tokenBReceived
    );

    if (_swapNeeded) {
      ISwap.SwapParams memory _sp;

      _sp.tokenIn = _tokenFrom;
      _sp.tokenOut = _tokenTo;
      _sp.amountIn = GMXManager.calcAmountInMaximum(
        self,
        _tokenFrom,
        _tokenTo,
        _tokenToAmt
      );
      _sp.amountOut = _tokenToAmt;
      _sp.slippage = self.swapSlippage;
      _sp.deadline = block.timestamp;
      // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
      // We allow deadline to be set as the current block timestamp whenever this function
      // is called because this function is triggered as a follow up function (by a callback/keeper)
      // and not directly by a user/keeper. If this follow on function flow reverts due to this tx
      // being processed after a set deadline, this will cause the vault to be in a "stuck" state.
      // To resolve this, this function will have to be called again with an updated deadline until it
      // succeeds/a miner processes the tx.

      GMXManager.swapTokensForExactTokens(self, _sp);
    }

    // Check for sufficient balance to repay, if not repay balance
    uint256 _tokenABalance = IERC20(self.tokenA).balanceOf(address(self.vault));
    uint256 _tokenBBalance = IERC20(self.tokenB).balanceOf(address(self.vault));

    _rp.repayTokenAAmt = _rp.repayTokenAAmt > _tokenABalance ? _tokenABalance : _rp.repayTokenAAmt;
    _rp.repayTokenBAmt = _rp.repayTokenBAmt > _tokenBBalance ? _tokenBBalance : _rp.repayTokenBAmt;

    GMXManager.repay(
      self,
      _rp.repayTokenAAmt,
      _rp.repayTokenBAmt
    );

    emit EmergencyRepaid(_rp.repayTokenAAmt, _rp.repayTokenBAmt);
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function emergencyBorrow(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeEmergencyBorrowChecks(self);

    // Re-borrow assets
    uint256 _depositValue = GMXReader.convertToUsdValue(
      self,
      address(self.tokenA),
      self.tokenA.balanceOf(address(this))
    )
    + GMXReader.convertToUsdValue(
      self,
      address(self.tokenB),
      self.tokenB.balanceOf(address(this))
    );

    (
      uint256 _borrowTokenAAmt,
      uint256 _borrowTokenBAmt
    ) = GMXManager.calcBorrow(self, _depositValue);

    GMXManager.borrow(self, _borrowTokenAAmt, _borrowTokenBAmt);

    self.status = GMXTypes.Status.Paused;

    emit EmergencyBorrowed(_borrowTokenAAmt, _borrowTokenBAmt);
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function emergencyResume(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeEmergencyResumeChecks(self);

    self.shouldEmergencyPause = false;
    self.status = GMXTypes.Status.Resume;
    self.refundee = payable(msg.sender);

    // Add liquidity
    GMXTypes.AddLiquidityParams memory _alp;

    _alp.tokenAAmt = self.tokenA.balanceOf(address(this));
    _alp.tokenBAmt = self.tokenB.balanceOf(address(this));

    // Get deposit value of all tokens in vault
    uint256 _depositValueForAddingLiquidity = GMXReader.convertToUsdValue(
      self,
      address(self.tokenA),
      _alp.tokenAAmt
    ) + GMXReader.convertToUsdValue(
      self,
      address(self.tokenB),
      _alp.tokenBAmt
    );

    _alp.minMarketTokenAmt = GMXManager.calcMinMarketSlippageAmt(
      self,
      _depositValueForAddingLiquidity,
      self.liquiditySlippage
    );
    _alp.executionFee = msg.value;

    // reset lastFeeCollected to block.timestamp to avoid having users pay for
    // fees while vault was paused
    self.lastFeeCollected = block.timestamp;

    GMXManager.addLiquidity(
      self,
      _alp
    );

    self.status = GMXTypes.Status.Resume;
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function processEmergencyResume(
    GMXTypes.Store storage self,
    uint256 lpAmtReceived
  ) external {
    GMXChecks.beforeProcessEmergencyResumeChecks(self);

    self.lpAmt += lpAmtReceived;

    self.status = GMXTypes.Status.Open;

    emit EmergencyResumed();
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function processEmergencyResumeCancellation(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeProcessEmergencyResumeCancellationChecks(self);

    self.status = GMXTypes.Status.Paused;

    emit EmergencyResumedCancelled();
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
  */
  function emergencyClose(
    GMXTypes.Store storage self
  ) external {
    GMXChecks.beforeEmergencyCloseChecks(self);

    // If rewardToken != tokenB, swap rewardToken to tokenB
    if (address(self.rewardToken) != address(self.tokenB)) {
      ISwap.SwapParams memory _sp;

      _sp.tokenIn = address(self.rewardToken);
      _sp.tokenOut = address(self.tokenB);
      _sp.amountIn = self.rewardToken.balanceOf(address(this));
      _sp.amountOut = 0; // amount out minimum calculated in Swap
      _sp.slippage = self.swapSlippage;
      _sp.deadline = block.timestamp;
      // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
      // We allow deadline to be set as the current block timestamp whenever this function
      // is called because this function is triggered as a follow up function (by a callback/keeper)
      // and not directly by a user/keeper. If this follow on function flow reverts due to this tx
      // being processed after a set deadline, this will cause the vault to be in a "stuck" state.
      // To resolve this, this function will have to be called again with an updated deadline until it
      // succeeds/a miner processes the tx.

      GMXManager.swapExactTokensForTokens(self, _sp);
    }

    self.status = GMXTypes.Status.Closed;

    emit EmergencyClosed();
  }

  /**
    * @notice @inheritdoc GMXVault
    * @param self GMXTypes.Store
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

