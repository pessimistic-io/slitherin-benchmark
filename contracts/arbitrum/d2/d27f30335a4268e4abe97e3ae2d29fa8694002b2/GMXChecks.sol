// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { IDeposit } from "./IDeposit.sol";
import { IWithdrawal } from "./IWithdrawal.sol";
import { IEvent } from "./IEvent.sol";
import { IOrder } from "./IOrder.sol";
import { Errors } from "./Errors.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXReader } from "./GMXReader.sol";

/**
  * @title GMXChecks
  * @author Steadefi
  * @notice Re-usable library functions for require function checks for Steadefi leveraged vaults
*/
library GMXChecks {

  /* ====================== CONSTANTS ======================== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  uint256 public constant MINIMUM_VALUE = 9e16;

  /* ===================== VIEW FUNCTIONS ==================== */

  /**
    * @notice Checks before native token deposit
    * @param self GMXTypes.Store
    * @param dp GMXTypes.DepositParams
  */
  function beforeNativeDepositChecks(
    GMXTypes.Store storage self,
    GMXTypes.DepositParams memory dp
  ) external view {
    if (dp.token != address(self.WNT))
      revert Errors.InvalidNativeTokenAddress();

    if (
      address(self.tokenA) != address(self.WNT) &&
      address(self.tokenB) != address(self.WNT)
    ) revert Errors.OnlyNonNativeDepositToken();

    if (msg.value <= 0) revert Errors.EmptyDepositAmount();

    if (dp.amt + dp.executionFee != msg.value)
      revert Errors.DepositAndExecutionFeeDoesNotMatchMsgValue();
  }

  /**
    * @notice Checks before token deposit
    * @param self GMXTypes.Store
    * @param depositValue USD value in 1e18
  */
  function beforeDepositChecks(
    GMXTypes.Store storage self,
    uint256 depositValue
  ) external view {
    if (self.status != GMXTypes.Status.Open)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.depositCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.depositCache.depositParams.executionFee < self.minExecutionFee)
      revert Errors.InsufficientExecutionFeeAmount();

    if (!self.vault.isTokenWhitelisted(self.depositCache.depositParams.token))
      revert Errors.InvalidDepositToken();

    if (self.depositCache.depositParams.amt <= 0)
      revert Errors.InsufficientDepositAmount();

    if (self.depositCache.depositParams.slippage < self.minSlippage)
      revert Errors.InsufficientSlippageAmount();

    if (depositValue == 0)
      revert Errors.InsufficientDepositAmount();

    if (depositValue < MINIMUM_VALUE)
      revert Errors.InsufficientDepositAmount();

    if (depositValue > GMXReader.additionalCapacity(self))
      revert Errors.InsufficientLendingLiquidity();
  }

  /**
    * @notice Checks before processing deposit
    * @param self GMXTypes.Store
  */
  function beforeProcessDepositChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Deposit)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.depositCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.depositCache.depositKey == bytes32(0))
      revert Errors.InvalidDepositKey();
  }

  /**
    * @notice Checks after deposit
    * @param self GMXTypes.Store
  */
  function afterDepositChecks(
    GMXTypes.Store storage self
  ) external view {
    if (
      self.depositCache.sharesToUser <
      self.depositCache.depositParams.minSharesAmt
    ) revert Errors.InsufficientSharesMinted();

    // Guards: check that equity did not decrease
    if (
      self.depositCache.healthParams.equityAfter <
      self.depositCache.healthParams.equityBefore
    ) revert Errors.InvalidEquity();

    // Guards: check that lpAmt did not decrease
    if (GMXReader.lpAmt(self) < self.depositCache.healthParams.lpAmtBefore)
      revert Errors.InsufficientLPTokensMinted();

    // Guards: check that debt ratio is within step change range
    if (!_isWithinStepChange(
      self.depositCache.healthParams.debtRatioBefore,
      GMXReader.debtRatio(self),
      self.debtRatioStepThreshold
    )) revert Errors.InvalidDebtRatio();
  }

  /**
    * @notice Checks before processing deposit cancellation
    * @param self GMXTypes.Store
  */
  function beforeProcessDepositCancellationChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Deposit)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.depositCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.depositCache.depositKey == bytes32(0))
      revert Errors.InvalidDepositKey();
  }

  /**
    * @notice Checks before processing after deposit check failure
    * @param self GMXTypes.Store
  */
  function beforeProcessAfterDepositFailureChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Deposit_Failed)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.depositCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.depositCache.depositKey == bytes32(0))
      revert Errors.InvalidDepositKey();
  }

  /**
    * @notice Checks before processing after deposit failure's liquidity withdrawn
    * @param self GMXTypes.Store
  */
  function beforeProcessAfterDepositFailureLiquidityWithdrawal(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Deposit_Failed)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.depositCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.depositCache.depositKey == bytes32(0))
      revert Errors.InvalidDepositKey();

    if (self.depositCache.withdrawKey == bytes32(0))
      revert Errors.InvalidWithdrawKey();
  }

  /**
    * @notice Checks before vault withdrawal
    * @param self GMXTypes.Store

  */
  function beforeWithdrawChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Open)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.withdrawCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (!self.vault.isTokenWhitelisted(self.withdrawCache.withdrawParams.token))
      revert Errors.InvalidWithdrawToken();

    if (self.withdrawCache.withdrawParams.shareAmt <= 0)
      revert Errors.EmptyWithdrawAmount();

    if (
      self.withdrawCache.withdrawParams.shareAmt >
      IERC20(address(self.vault)).balanceOf(self.withdrawCache.user)
    ) revert Errors.InsufficientWithdrawBalance();

    if (self.withdrawCache.withdrawValue < MINIMUM_VALUE)
      revert Errors.InsufficientWithdrawAmount();

    if (self.withdrawCache.withdrawParams.slippage < self.minSlippage)
      revert Errors.InsufficientSlippageAmount();

    if (self.withdrawCache.withdrawParams.executionFee < self.minExecutionFee)
      revert Errors.InsufficientExecutionFeeAmount();

    if (self.withdrawCache.withdrawParams.executionFee != msg.value)
      revert Errors.InvalidExecutionFeeAmount();
  }

  /**
    * @notice Checks before processing vault withdrawal
    * @param self GMXTypes.Store
  */
  function beforeProcessWithdrawChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Withdraw)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.withdrawCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.withdrawCache.withdrawKey == bytes32(0))
      revert Errors.InvalidWithdrawKey();
  }

  /**
    * @notice Checks after token withdrawal
    * @param self GMXTypes.Store
  */
  function afterWithdrawChecks(
    GMXTypes.Store storage self
  ) external view {
    if (
      self.withdrawCache.tokensToUser <
      self.withdrawCache.withdrawParams.minWithdrawTokenAmt
    ) revert Errors.InsufficientAssetsReceived();

    // Guards: check that equity did not increase
    if (
      self.withdrawCache.healthParams.equityAfter >
      self.withdrawCache.healthParams.equityBefore
    ) revert Errors.InvalidEquity();

    // Guards: check that lpAmt did not increase
    if (GMXReader.lpAmt(self) > self.withdrawCache.healthParams.lpAmtBefore)
      revert Errors.InsufficientLPTokensBurned();

    // Guards: check that debt ratio is within step change range
    if (!_isWithinStepChange(
      self.withdrawCache.healthParams.debtRatioBefore,
      GMXReader.debtRatio(self),
      self.debtRatioStepThreshold
    )) revert Errors.InvalidDebtRatio();
  }

  /**
    * @notice Checks before processing withdrawal cancellation
    * @param self GMXTypes.Store
  */
  function beforeProcessWithdrawCancellationChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Withdraw)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.withdrawCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.withdrawCache.withdrawKey == bytes32(0))
      revert Errors.InvalidWithdrawKey();
  }

  /**
    * @notice Checks before processing after withdrawal failure
    * @param self GMXTypes.Store
  */
  function beforeProcessAfterWithdrawFailureChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Withdraw_Failed)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.withdrawCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.withdrawCache.withdrawKey == bytes32(0))
      revert Errors.InvalidWithdrawKey();
  }

  /**
    * @notice Checks before processing after withdraw failure's liquidity added
    * @param self GMXTypes.Store
  */
  function beforeProcessAfterWithdrawFailureLiquidityAdded(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Withdraw_Failed)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.withdrawCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.withdrawCache.withdrawKey == bytes32(0))
      revert Errors.InvalidWithdrawKey();

    if (self.withdrawCache.depositKey == bytes32(0))
      revert Errors.InvalidDepositKey();
  }

  /**
    * @notice Checks before rebalancing delta
    * @param self GMXTypes.Store
  */
  function beforeRebalanceDeltaChecks(
    GMXTypes.Store storage self
  ) external view {
    if (
      self.status != GMXTypes.Status.Open &&
      self.status != GMXTypes.Status.Rebalance_Open
    ) revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.InvalidRefundeeAddress();

    if (self.delta == GMXTypes.Delta.Neutral) {
      if (
        self.rebalanceCache.healthParams.deltaBefore < self.deltaUpperLimit &&
        self.rebalanceCache.healthParams.deltaBefore > self.deltaLowerLimit
      ) revert Errors.InvalidRebalancePreConditions();
    }

    // Delta rebalancing does not apply to Long Strategy
    if (self.delta == GMXTypes.Delta.Long)
      revert Errors.InvalidRebalancePreConditions();
  }

  /**
    * @notice Checks before rebalancing debt
    * @param self GMXTypes.Store
  */
  function beforeRebalanceDebtChecks(
    GMXTypes.Store storage self
  ) external view {
    if (
      self.status != GMXTypes.Status.Open &&
      self.status != GMXTypes.Status.Rebalance_Open
    ) revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.InvalidRefundeeAddress();

    // Check that rebalance conditions have been met
    if (
      self.rebalanceCache.healthParams.debtRatioBefore < self.debtRatioUpperLimit &&
      self.rebalanceCache.healthParams.debtRatioBefore > self.debtRatioLowerLimit
    ) revert Errors.InvalidRebalancePreConditions();
  }

  /**
    * @notice Checks before processing of rebalancing add or remove
    * @param self GMXTypes.Store
  */
  function beforeProcessRebalanceChecks(
    GMXTypes.Store storage self
  ) external view {
    if (
      self.status != GMXTypes.Status.Rebalance_Add &&
      self.status != GMXTypes.Status.Rebalance_Remove
    ) revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @notice Checks after rebalancing add or remove
    * @param self GMXTypes.Store
  */
  function afterRebalanceChecks(
    GMXTypes.Store storage self
  ) external view {
    // Guards: check that delta is within limits for Neutral strategy
    if (self.delta == GMXTypes.Delta.Neutral) {
      if (
        GMXReader.delta(self) > self.deltaUpperLimit &&
        GMXReader.delta(self) < self.deltaLowerLimit
      ) revert Errors.InvalidDelta();
    }

    // Guards: check that debt is within limits for Long/Neutral strategy
    if (
      GMXReader.debtRatio(self) > self.debtRatioUpperLimit &&
      GMXReader.debtRatio(self) < self.debtRatioLowerLimit
    ) revert Errors.InvalidDebtRatio();
  }

  /**
    * @notice Checks before compound
    * @param self GMXTypes.Store
  */
  function beforeCompoundChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Open)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.InvalidRefundeeAddress();

    if (
      self.compoundCache.compoundParams.depositParams.executionFee <
      self.minExecutionFee
    ) revert Errors.InsufficientExecutionFeeAmount();

    if (self.compoundCache.depositValue <= 0)
      revert Errors.InsufficientDepositAmount();
  }

  /**
    * @notice Checks before processing compound
    * @param self GMXTypes.Store
  */
  function beforeProcessCompoundChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Compound)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @notice Checks before processing compound cancellation
    * @param self GMXTypes.Store
  */
  function beforeProcessCompoundCancellationChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Compound)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @notice Checks before emergency pause of vault
    * @param self GMXTypes.Store
  */
  function beforeEmergencyPauseChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Open)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @notice Checks before emergency closure of vault
    * @param self GMXTypes.Store
  */
  function beforeEmergencyCloseChecks (
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Paused)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @notice Checks before resuming vault
    * @param self GMXTypes.Store
  */
  function beforeEmergencyResumeChecks (
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Paused)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @notice Checks before a withdrawal during emergency closure
    * @param self GMXTypes.Store
    * @param shareAmt Amount of shares to burn
  */
  function beforeEmergencyWithdrawChecks(
    GMXTypes.Store storage self,
    uint256 shareAmt
  ) external view {
    if (self.status != GMXTypes.Status.Closed)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (shareAmt <= 0)
      revert Errors.EmptyWithdrawAmount();

    if (shareAmt > IERC20(address(self.vault)).balanceOf(self.withdrawCache.user))
      revert Errors.InsufficientWithdrawBalance();
  }

  /* ================== INTERNAL FUNCTIONS =================== */

  /**
    * @notice Check if values are within threshold range
    * @param valueBefore Previous value
    * @param valueAfter New value
    * @param threshold Tolerance threshold; 100 = 1%
    * @return boolean Whether value after is within threshold range
  */
  function _isWithinStepChange(
    uint256 valueBefore,
    uint256 valueAfter,
    uint256 threshold
  ) internal pure returns (bool) {
    // To bypass initial vault deposit
    if (valueBefore == 0)
      return true;

    return (
      valueAfter >= valueBefore * (10000 - threshold) / 10000 &&
      valueAfter <= valueBefore * (10000 + threshold) / 10000
    );
  }
}

