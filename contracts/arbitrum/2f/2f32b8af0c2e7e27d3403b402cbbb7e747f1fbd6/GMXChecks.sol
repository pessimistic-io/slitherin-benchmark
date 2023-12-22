// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IDeposit } from "./IDeposit.sol";
import { IWithdrawal } from "./IWithdrawal.sol";
import { IEvent } from "./IEvent.sol";
import { IOrder } from "./IOrder.sol";
import { Errors } from "./Errors.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXReader } from "./GMXReader.sol";

library GMXChecks {

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  uint256 public constant MINIMUM_VALUE = 9e16;

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * @dev Checks before native token deposits
    * @param self Vault store data
    * @param dp DepositParams struct
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
    * @dev Checks before token deposits
    * @param self Vault store data
    * @param depositValue Deposit value (USD) in 1e18
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
    * @dev Checks during processing deposit
    * @param self Vault store data
  */
  function beforeProcessDepositChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Deposit)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.InvalidRefundeeAddress();

    if (self.depositCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.depositCache.depositKey == bytes32(0))
      revert Errors.InvalidDepositKey();
  }

  /**
    * @dev Checks after token deposits
    * @param self Vault store data
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
    * @dev Checks before processing deposit cancellation
    * @param self Vault store data
  */
  function beforeProcessDepositCancellationChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Deposit)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.InvalidRefundeeAddress();

    if (self.depositCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.depositCache.depositKey == bytes32(0))
      revert Errors.InvalidDepositKey();
  }

  /**
    * @dev Checks before processing after deposit checks failure
    * @param self Vault store data
  */
  function beforeProcessAfterDepositFailureChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Deposit_Failed)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.InvalidRefundeeAddress();

    if (self.depositCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.depositCache.depositKey == bytes32(0))
      revert Errors.InvalidDepositKey();
  }

  /**
    * @dev Checks before processing after deposit failure liquidity withdrawn
    * @param self Vault store data
  */
  function beforeProcessAfterDepositFailureLiquidityWithdrawal(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Deposit_Failed)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.InvalidRefundeeAddress();

    if (self.depositCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.depositCache.depositKey == bytes32(0))
      revert Errors.InvalidDepositKey();

    if (self.depositCache.withdrawKey == bytes32(0))
      revert Errors.InvalidWithdrawKey();
  }

  /**
    * @dev Checks before vault withdrawals
    * @param self Vault store data

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
    * @dev Checks before processing repayment
    * @param self Vault store data
  */
  function beforeProcessWithdrawChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Withdraw)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.InvalidRefundeeAddress();

    if (self.withdrawCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.withdrawCache.withdrawKey == bytes32(0))
      revert Errors.InvalidWithdrawKey();
  }

  /**
    * @dev Checks after token withdrawals
    * @param self Vault store data
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
    * @dev Checks before processing withdrawal cancellation
    * @param self Vault store data
  */
  function beforeProcessWithdrawCancellationChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Withdraw)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.InvalidRefundeeAddress();

    if (self.withdrawCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.withdrawCache.withdrawKey == bytes32(0))
      revert Errors.InvalidWithdrawKey();
  }

  /**
    * @dev Checks before processing after withdraw checks failure
    * @param self Vault store data
  */
  function beforeProcessAfterWithdrawFailureChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Withdraw_Failed)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.InvalidRefundeeAddress();

    if (self.withdrawCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.withdrawCache.withdrawKey == bytes32(0))
      revert Errors.InvalidWithdrawKey();
  }

  /**
    * @dev Checks before processing after withdraw failure liquidity withdrawn
    * @param self Vault store data
  */
  function beforeProcessAfterWithdrawFailureLiquidityAdded(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Withdraw_Failed)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.InvalidRefundeeAddress();

    if (self.withdrawCache.user == address(0))
      revert Errors.ZeroAddressNotAllowed();

    if (self.withdrawCache.withdrawKey == bytes32(0))
      revert Errors.InvalidWithdrawKey();

    if (self.withdrawCache.depositKey == bytes32(0))
      revert Errors.InvalidDepositKey();
  }

  /**
    * @dev Checks before rebalancing delta
    * @param self Vault store data
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
    * @dev Checks before rebalancing debt
    * @param self Vault store data
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
    * @dev Checks during processing of rebalancing by adding liquidity
    * @param self Vault store data
  */
  function beforeProcessRebalanceChecks(
    GMXTypes.Store storage self
  ) external view {
    if (
      self.status != GMXTypes.Status.Rebalance_Add &&
      self.status != GMXTypes.Status.Rebalance_Remove
    ) revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.InvalidRefundeeAddress();
  }

  /**
    * @dev Checks after rebalancing add liquidity
    * @param self Vault store data
  */
  function afterRebalanceChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.rebalanceCache.rebalanceType == GMXTypes.RebalanceType.Delta) {
      // Guards: check that delta is within global limits
      if (
        GMXReader.delta(self) > self.deltaUpperLimit &&
        GMXReader.delta(self) < self.deltaLowerLimit
      ) revert Errors.InvalidDelta();
    } else if (self.rebalanceCache.rebalanceType == GMXTypes.RebalanceType.Debt) {
      // Guards: check that debt ratio is within global limits
      if (
        GMXReader.debtRatio(self) > self.debtRatioUpperLimit &&
        GMXReader.debtRatio(self) < self.debtRatioLowerLimit
      ) revert Errors.InvalidDebtRatio();
    }
  }

  /**
    * @dev Checks before processing compound
    * @param self Vault store data
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
    * @dev Checks before processing compound
    * @param self Vault store data
  */
  function beforeProcessCompoundChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Compound)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.InvalidRefundeeAddress();
  }

  /**
    * @dev Checks before processing compound failure
    * @param self Vault store data
  */
  function beforeProcessCompoundCancellationChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Compound)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.InvalidRefundeeAddress();
  }

  /**
    * @dev Checks before shutdown of vault in emergency
    * @param self Vault store data
  */
  function beforeEmergencyShutdownChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Open)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @dev Checks before repayment of debt and vault closure after emergency shutdown
    * @param self Vault store data
  */
  function beforeEmergencyCloseChecks (
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Emergency_Shutdown)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @dev Checks before resuming vault again after an emergency shutdown
    * @param self Vault store data
  */
  function beforeEmergencyResumeChecks (
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Emergency_Shutdown)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @dev Checks before emergency withdrawals
    * @param self Vault store data
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
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
    * @dev Helper function to check if values are within threshold range
    * @param valueBefore Previous value
    * @param valueAfter New value
    * @param threshold Tolerance threshold; 100 = 1%
    * @return Whether value after is within threshold range
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

