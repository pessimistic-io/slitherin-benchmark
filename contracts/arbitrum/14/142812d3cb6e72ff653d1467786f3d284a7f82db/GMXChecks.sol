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
  uint256 public constant DUST_AMOUNT = 1e17;

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
    if (address(self.tokenA) != address(self.WNT))
      revert Errors.OnlyNonNativeDepositToken();
    if (address(self.tokenB) != address(self.WNT))
      revert Errors.OnlyNonNativeDepositToken();

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

    GMXTypes.DepositCache memory _dc = self.depositCache;

    if (_dc.depositParams.executionFee < self.minExecutionFee)
      revert Errors.InsufficientExecutionFeeAmount();

    if (!self.vault.isTokenWhitelisted(_dc.depositParams.token))
      revert Errors.InvalidDepositToken();

    if (_dc.depositParams.amt <= 0)
      revert Errors.InsufficientDepositAmount();

    if (depositValue <= 0)
      revert Errors.InsufficientDepositAmount();

    if (depositValue < DUST_AMOUNT)
      revert Errors.InsufficientDepositAmount();

    if (depositValue > GMXReader.additionalCapacity(self))
      revert Errors.InsufficientLendingLiquidity();
  }

  /**
    * @dev Checks during processing deposit
    * @param self Vault store data
  */
  function processMintChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Mint)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (self.refundee == address(0))
      revert Errors.InvalidRefundeeAddress();

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
    GMXTypes.DepositCache memory _dc = self.depositCache;

    if (self.status != GMXTypes.Status.Mint)
      revert Errors.NotAllowedInCurrentVaultStatus();

    // TODO do we  really need a maxCapacity for strategy vaults...?
    // if (dc.healthParams.equityAfter > self.maxCapacity)
    //   revert Errors.InsufficientCapacity();

    if (
      _dc.sharesToUser <
      _dc.depositParams.minSharesAmt
    ) revert Errors.InsufficientSharesMinted();

    // Invariant: check that equity did not decrease
    if (
      _dc.healthParams.equityAfter <
      _dc.healthParams.equityBefore
    ) revert Errors.InvalidEquity();

    // Invariant: check that lpAmt did not decrease
    if (GMXReader.lpAmt(self) < _dc.healthParams.lpAmtBefore)
      revert Errors.InsufficientLPTokensMinted();

    // Invariant: check that debt ratio is within step change range
    if (!_isWithinRange(
      _dc.healthParams.debtRatioBefore,
      GMXReader.debtRatio(self),
      self.debtRatioStepThreshold
    )) revert Errors.InvalidDebtRatio();

    // Invariant: check that delta is within step change range
    if (self.delta == GMXTypes.Delta.Neutral) {
      if (!_isWithinRange(
        uint256(_dc.healthParams.deltaBefore),
        uint256(GMXReader.delta(self)),
        self.deltaStepThreshold
      )) revert Errors.InvalidDelta();
    }
  }

  /**
    * @dev Checks before vault withdrawals
    * @param self Vault store data

  */
  function beforeWithdrawChecks(
    GMXTypes.Store storage self
  ) external view {
    GMXTypes.WithdrawCache memory _wc = self.withdrawCache;

    if (self.status != GMXTypes.Status.Open)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (!self.vault.isTokenWhitelisted(_wc.withdrawParams.token))
      revert Errors.InvalidWithdrawToken();

    if (block.number == self.lastDepositBlock)
      revert Errors.WithdrawNotAllowedInSameDepositBlock();

    if (_wc.withdrawParams.shareAmt <= 0)
      revert Errors.EmptyWithdrawAmount();

    if (_wc.withdrawParams.executionFee < self.minExecutionFee)
      revert Errors.InsufficientExecutionFeeAmount();

    if (msg.value <= 0) revert Errors.InvalidExecutionFeeAmount();

    if (_wc.withdrawParams.executionFee != msg.value)
      revert Errors.InvalidExecutionFeeAmount();
  }

  /**
    * @dev Checks before processing repayment
    * @param self Vault store data
  */
  function processSwapForRepayChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Swap_For_Repay)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @dev Checks before processing of swap for repay after removing liquidity
    * @param self Vault store data
  */
  function processRepayChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Repay)
      revert Errors.NotAllowedInCurrentVaultStatus();

      revert Errors.InvalidWithdrawKey();
  }

  /**
    * @dev Checks before processing withdrawal
    * @param self Vault store data
  */
  function processBurnChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Withdraw)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @dev Checks after token withdrawals
    * @param self Vault store data
  */
  function afterWithdrawChecks(
    GMXTypes.Store storage self
  ) external view {
    GMXTypes.WithdrawCache memory _wc = self.withdrawCache;

    if (
      _wc.tokensToUser <
      _wc.withdrawParams.minWithdrawTokenAmt
    ) revert Errors.InsufficientAssetsReceived();

    // Invariant: check that equity did not increase
    if (
      _wc.healthParams.equityAfter >
      _wc.healthParams.equityBefore
    ) revert Errors.InvalidEquity();

    // Invariant: check that lpAmt did not increase
    if (GMXReader.lpAmt(self) > _wc.healthParams.lpAmtBefore)
      revert Errors.InsufficientLPTokensBurned();

    // Invariant: check that debt ratio is within step change range
    if (!_isWithinRange(
      _wc.healthParams.debtRatioBefore,
      GMXReader.debtRatio(self),
      self.debtRatioStepThreshold
    )) revert Errors.InvalidDebtRatio();

    // Invariant: check that delta is within step change range
    if (self.delta == GMXTypes.Delta.Neutral) {
      if (!_isWithinRange(
        uint256(_wc.healthParams.deltaBefore),
        uint256(GMXReader.delta(self)),
        self.deltaStepThreshold
      )) revert Errors.InvalidDelta();
    }
  }

  /**
    * @dev Checks before rebalancing add liquidity
    * @param self Vault store data
  */
  function beforeRebalanceAddChecks(
    GMXTypes.Store storage self
  ) external view {
    GMXTypes.RebalanceAddCache memory _rac =
      self.rebalanceAddCache;

    if (self.status != GMXTypes.Status.Open)
      revert Errors.NotAllowedInCurrentVaultStatus();

    // Check that rebalance conditions have been met
    if (
      _rac.healthParams.debtRatioBefore <= self.debtRatioUpperLimit ||
      _rac.healthParams.debtRatioBefore >= self.debtRatioLowerLimit
    ) revert Errors.InvalidRebalancePreConditions();

    if (self.delta == GMXTypes.Delta.Neutral) {
      if (
        _rac.healthParams.deltaBefore <= self.deltaUpperLimit ||
        _rac.healthParams.deltaBefore >= self.deltaLowerLimit
      ) revert Errors.InvalidRebalancePreConditions();
    }
  }

  /**
    * @dev Checks during processing of rebalancing by adding liquidity
    * @param self Vault store data
  */
  function processRebalanceAddChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Rebalance_Add_Add_Liquidity)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @dev Checks after rebalancing add liquidity
    * @param self Vault store data
  */
  function afterRebalanceAddChecks(
    GMXTypes.Store storage self
  ) external view {
    GMXTypes.RebalanceAddCache memory _rac =
      self.rebalanceAddCache;

    // Invariant: check that lpAmt did not decrease
    if (
      GMXReader.lpAmt(self) < _rac.healthParams.lpAmtBefore
    ) revert Errors.InsufficientLPTokensMinted();

    // Invariant: check that debt amt did not decrease
    (
      uint256 _debtAmtTokenAAfter,
      uint256 _debtAmtTokenBAfter
    ) = GMXReader.debtAmt(self);

    if (
      _debtAmtTokenAAfter < _rac.healthParams.debtAmtTokenABefore ||
      _debtAmtTokenBAfter < _rac.healthParams.debtAmtTokenBBefore
    ) revert Errors.InvalidRebalanceDebtAmounts();

    // Invariant: check that debt ratio is within global limits
    if (
      GMXReader.debtRatio(self) > self.debtRatioUpperLimit ||
      GMXReader.debtRatio(self) < self.debtRatioLowerLimit
    ) revert Errors.InvalidDebtRatio();

    // Invariant: check that delta is within global limits
    if (
      GMXReader.delta(self) > self.deltaUpperLimit ||
      GMXReader.delta(self) < self.deltaLowerLimit
    ) revert Errors.InvalidDelta();
  }

  /**
    * @dev Checks before rebalancing remove liquidity
    * @param self Vault store data
  */
  function beforeRebalanceRemoveChecks(
    GMXTypes.Store storage self
  ) external view {
    GMXTypes.RebalanceRemoveCache memory _rrc =
      self.rebalanceRemoveCache;

    if (self.status != GMXTypes.Status.Rebalance_Remove)
      revert Errors.NotAllowedInCurrentVaultStatus();

    // Check that rebalance conditions have been met
    if (
      _rrc.healthParams.debtRatioBefore <= self.debtRatioUpperLimit ||
      _rrc.healthParams.debtRatioBefore >= self.debtRatioLowerLimit
    ) revert Errors.InvalidRebalancePreConditions();

    if (self.delta == GMXTypes.Delta.Neutral) {
      if (
        _rrc.healthParams.deltaBefore <= self.deltaUpperLimit ||
        _rrc.healthParams.deltaBefore >= self.deltaLowerLimit
      ) revert Errors.InvalidRebalancePreConditions();
    }
  }

  /**
    * @dev Checks during processing of rebalancing by removing liquidity, checking if swaps needed
    * @param self Vault store data
  */
  function processRebalanceRemoveSwapForRepayChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Rebalance_Remove_Swap_For_Repay)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @dev Checks during processing of rebalancing by removing liquidity, making repayments after swaps
    * @param self Vault store data
  */
  function processRebalanceRemoveRepayChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Rebalance_Remove_Repay)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @dev Checks during processing of rebalancing by removing liquidity, making repayments after swaps
    * @param self Vault store data
  */
  function processRebalanceRemoveAddLiquidityChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Rebalance_Remove_Add_Liquidity)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @dev Checks after rebalancing remove liquidity
    * @param self Vault store data
  */
  function afterRebalanceRemoveChecks(
    GMXTypes.Store storage self
  ) external view {
    GMXTypes.RebalanceRemoveCache memory _rrc =
      self.rebalanceRemoveCache;

    // Invariant: check that lpAmt did not increase
    if (
      GMXReader.lpAmt(self) > _rrc.healthParams.lpAmtBefore
    ) revert Errors.InsufficientLPTokensMinted();

    // Invariant: check that debt amt did not increase
    (
      uint256 _debtAmtTokenAAfter,
      uint256 _debtAmtTokenBAfter
    ) = GMXReader.debtAmt(self);

    if (
      _debtAmtTokenAAfter > _rrc.healthParams.debtAmtTokenABefore ||
      _debtAmtTokenBAfter > _rrc.healthParams.debtAmtTokenBBefore
    ) revert Errors.InvalidRebalanceDebtAmounts();

    // Invariant: check that debt ratio is within global limits
    if (
      GMXReader.debtRatio(self) > self.debtRatioUpperLimit ||
      GMXReader.debtRatio(self) < self.debtRatioLowerLimit
    ) revert Errors.InvalidDebtRatio();

    // Invariant: check that delta is within global limits
    if (
      GMXReader.delta(self) > self.deltaUpperLimit ||
      GMXReader.delta(self) < self.deltaLowerLimit
    ) revert Errors.InvalidDelta();
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
  }

  /**
    * @dev Checks before processing compound
    * @param self Vault store data
  */
  function processCompoundAddChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Compound_Add_Liquidity)
      revert Errors.NotAllowedInCurrentVaultStatus();

    GMXTypes.CompoundCache memory _cc = self.compoundCache;

    if (
      _cc.compoundParams.depositParams.executionFee <
      self.minExecutionFee
    ) revert Errors.InsufficientExecutionFeeAmount();

    if (_cc.depositValue <= 0)
      revert Errors.InsufficientDepositAmount();

    if (_cc.depositValue < DUST_AMOUNT)
      revert Errors.InsufficientDepositAmount();
  }

  /**
    * @dev Checks before processing compound
    * @param self Vault store data
  */
  function processCompoundAddedChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Compound_Liquidity_Added)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @dev Checks before token deposits
    * @param self Vault store data
  */
  function beforeEmergencyShutdownChecks(
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Open)
      revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @dev Checks before token deposits
    * @param self Vault store data
    * * @param shareRatio Amount of debt to pay proportionate to vault's total supply of shares in 1e18; i.e. 100% = 1e18
  */
  function beforeEmergencyRepayChecks (
    GMXTypes.Store storage self,
    uint256 shareRatio
  ) external view {
    if (self.status != GMXTypes.Status.Closed)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (shareRatio <= 0 || shareRatio > SAFE_MULTIPLIER)
      revert Errors.InvalidShareRatioAmount();
  }

  /**
    * @dev Checks before token deposits
    * @param self Vault store data
  */
  function beforeEmergencyResumeChecks (
    GMXTypes.Store storage self
  ) external view {
    if (self.status != GMXTypes.Status.Closed)
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
  function _isWithinRange(
    uint256 valueBefore,
    uint256 valueAfter,
    uint256 threshold
  ) internal pure returns (bool) {
    // TODO To check if this is initial state which will result in valueBefore as 0
    // TODO also to check if emergency withdrawing.. if so, then valueAfter can be 0 as well?

    if (valueBefore == 0 || valueAfter == 0) {
      return true;
    }

    return (
      valueAfter >= valueBefore * (10000 - threshold) / 10000 &&
      valueAfter <= valueBefore * (10000 + threshold) / 10000
    );
  }
}

