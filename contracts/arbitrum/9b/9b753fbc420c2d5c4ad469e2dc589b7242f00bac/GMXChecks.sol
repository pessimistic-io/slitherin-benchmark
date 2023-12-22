// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IGMXDeposit } from "./IGMXDeposit.sol";
import { IGMXWithdrawal } from "./IGMXWithdrawal.sol";
import { IGMXEvent } from "./IGMXEvent.sol";
import { IGMXOrder } from "./IGMXOrder.sol";
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
  */
  function beforeDepositChecks(
    GMXTypes.Store storage self
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

    if (_dc.depositValue <= 0)
      revert Errors.InsufficientDepositAmount();

    if (_dc.depositValue <= DUST_AMOUNT)
      revert Errors.InsufficientDepositAmount();

    if (_dc.depositValue >= GMXReader.additionalCapacity(self))
      revert Errors.InsufficientLendingLiquidity();
  }

  /**
    * @dev Checks during processing deposit
    * @param self Vault store data
    * @param depositKey Deposit key hash to find deposit info
  */
  function processMintChecks(
    GMXTypes.Store storage self,
    bytes32 depositKey
  ) external view {
    GMXTypes.DepositCache memory _dc = self.depositCache;

    if (self.status != GMXTypes.Status.Mint)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (_dc.user == address(0))
      revert Errors.InvalidDepositKey();

    if (_dc.depositKey != depositKey)
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

    if (self.vault.isTokenWhitelisted(_wc.withdrawParams.token))
      revert Errors.InvalidWithdrawToken();

    // TODO this doesnt apply to GMX.. to remove?
    if (block.number == self.lastDepositBlock)
      revert Errors.WithdrawNotAllowedInSameDepositBlock();

    if (_wc.withdrawParams.shareAmt <= 0)
      revert Errors.EmptyWithdrawAmount();

    if (_wc.withdrawParams.executionFee < self.minExecutionFee)
      revert Errors.InsufficientExecutionFeeAmount();

    if (_wc.withdrawParams.swapForRepayParams.executionFee < self.minExecutionFee)
      revert Errors.InsufficientExecutionFeeAmount();

    if (_wc.withdrawParams.swapForWithdrawParams.executionFee < self.minExecutionFee)
      revert Errors.InsufficientExecutionFeeAmount();

    if (msg.value <= 0) revert Errors.InvalidExecutionFeeAmount();

    if (_wc.withdrawParams.executionFee +
        _wc.withdrawParams.swapForRepayParams.executionFee +
        _wc.withdrawParams.swapForWithdrawParams.executionFee != msg.value)
      revert Errors.InvalidExecutionFeeAmount();
  }

  /**
    * @dev Checks before processing repayment
    * @param self Vault store data
    * @param withdrawKey Withdraw key hash to find withdrawal info
  */
  function processSwapForRepayChecks(
    GMXTypes.Store storage self,
    bytes32 withdrawKey
  ) external view {
    GMXTypes.WithdrawCache memory _wc = self.withdrawCache;

    if (self.status != GMXTypes.Status.Swap_For_Repay)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (_wc.user == address(0))
      revert Errors.InvalidWithdrawKey();

    if (_wc.withdrawKey != withdrawKey)
      revert Errors.InvalidWithdrawKey();
  }

  /**
    * @dev Checks before processing of swap for repay after removing liquidity
    * @param self Vault store data
    * @param withdrawKey Withdraw key hash to find withdrawal info
    * @param orderKey Swap key hash to find withdrawKey hash
  */
  function processRepayChecks(
    GMXTypes.Store storage self,
    bytes32 withdrawKey,
    bytes32 orderKey
  ) external view {
    GMXTypes.WithdrawCache memory _wc = self.withdrawCache;

    if (self.status != GMXTypes.Status.Repay)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (_wc.user == address(0))
      revert Errors.InvalidWithdrawKey();

    if (_wc.withdrawKey != withdrawKey)
      revert Errors.InvalidWithdrawKey();

    // orderKey can be bytes32(0) if there is no swap needed for repay
    // but if not, we should check it is the same order key for the swap for repay performed
    if (
      _wc.withdrawParams.swapForRepayParams.orderKey != bytes32(0) &&
      _wc.withdrawParams.swapForRepayParams.orderKey != orderKey
    ) revert Errors.InvalidOrderKey();
  }

  /**
    * @dev Checks before processing swaps for withdrawal
    * @param self Vault store data
    * @param withdrawKey Withdraw key hash to find withdrawal info
  */
  function processSwapForWithdrawChecks(
    GMXTypes.Store storage self,
    bytes32 withdrawKey
  ) external view {
    GMXTypes.WithdrawCache memory _wc = self.withdrawCache;

    if (self.status != GMXTypes.Status.Swap_For_Withdraw)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (_wc.user == address(0))
      revert Errors.InvalidWithdrawKey();

    if (_wc.withdrawKey != withdrawKey)
      revert Errors.InvalidWithdrawKey();
  }

  /**
    * @dev Checks before processing withdrawal
    * @param self Vault store data
    * @param withdrawKey Withdraw key hash to find withdrawal info
    * @param orderKey Swap key hash to find withdrawKey hash
  */
  function processBurnChecks(
    GMXTypes.Store storage self,
    bytes32 withdrawKey,
    bytes32 orderKey
  ) external view {
    GMXTypes.WithdrawCache memory _wc = self.withdrawCache;

    if (self.status != GMXTypes.Status.Withdraw)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (_wc.user == address(0))
      revert Errors.InvalidWithdrawKey();

    if (_wc.withdrawKey != withdrawKey)
      revert Errors.InvalidWithdrawKey();

    // orderKey can be bytes32(0) if there is no swap needed for withdraw
    // but if not, we should check it is the same order key for the swap for withdraw performed
    if (
      _wc.withdrawParams.swapForWithdrawParams.orderKey != bytes32(0) &&
      _wc.withdrawParams.swapForWithdrawParams.orderKey != orderKey
    ) revert Errors.InvalidOrderKey();
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
      _wc.withdrawTokenAmt <
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
    * @param withdrawKey Withdraw key hash to find withdrawal info
  */
  function processRebalanceRemoveSwapForRepayChecks(
    GMXTypes.Store storage self,
    bytes32 withdrawKey
  ) external view {
    GMXTypes.RebalanceRemoveCache memory _rrc =
      self.rebalanceRemoveCache;

    if (self.status != GMXTypes.Status.Rebalance_Remove_Swap_For_Repay)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (_rrc.withdrawKey != withdrawKey)
      revert Errors.InvalidWithdrawKey();
  }

  /**
    * @dev Checks during processing of rebalancing by removing liquidity, making repayments after swaps
    * @param self Vault store data
    * @param withdrawKey Withdraw key
    * @param orderKey Order key hash
  */
  function processRebalanceRemoveRepayChecks(
    GMXTypes.Store storage self,
    bytes32 withdrawKey,
    bytes32 orderKey
  ) external view {
    GMXTypes.RebalanceRemoveCache memory _rrc =
      self.rebalanceRemoveCache;

    if (self.status != GMXTypes.Status.Rebalance_Remove_Repay)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (_rrc.withdrawKey != withdrawKey)
      revert Errors.InvalidWithdrawKey();

    // orderKey can be bytes32(0) if there is no swap needed for withdraw
    // but if not, we should check it is the same order key for the swap for withdraw performed
    if (
      _rrc.rebalanceRemoveParams.swapForRepayParams.orderKey != bytes32(0) &&
      _rrc.rebalanceRemoveParams.swapForRepayParams.orderKey != orderKey
    ) revert Errors.InvalidOrderKey();
  }

  /**
    * @dev Checks during processing of rebalancing by removing liquidity, making repayments after swaps
    * @param self Vault store data
    * @param depositKey Deposit key
  */
  function processRebalanceRemoveAddLiquidityChecks(
    GMXTypes.Store storage self,
    bytes32 depositKey
  ) external view {
    GMXTypes.RebalanceRemoveCache memory _rrc =
      self.rebalanceRemoveCache;

    if (self.status != GMXTypes.Status.Rebalance_Remove_Add_Liquidity)
      revert Errors.NotAllowedInCurrentVaultStatus();

    if (_rrc.depositKey != depositKey)
      revert Errors.InvalidWithdrawKey();
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

    // TEMP
    if (valueBefore == 0 || valueAfter == 0) {
      return true;
    }

    return (
      valueAfter >= valueBefore * (10000 - threshold) / 10000 &&
      valueAfter <= valueBefore * (10000 + threshold) / 10000
    );
  }
}

