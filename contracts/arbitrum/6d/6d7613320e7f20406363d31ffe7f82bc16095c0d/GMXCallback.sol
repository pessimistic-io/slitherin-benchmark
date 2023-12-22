// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IDeposit } from "./IDeposit.sol";
import { IWithdrawal } from "./IWithdrawal.sol";
import { IEvent } from "./IEvent.sol";
import { IDepositCallbackReceiver } from "./IDepositCallbackReceiver.sol";
import { IWithdrawalCallbackReceiver } from "./IWithdrawalCallbackReceiver.sol";
import { IRoleStore } from "./IRoleStore.sol";
import { IGMXVault } from "./IGMXVault.sol";
import { Errors } from "./Errors.sol";
import { GMXTypes } from "./GMXTypes.sol";

import { console } from "./console.sol";

contract GMXCallback is IDepositCallbackReceiver, IWithdrawalCallbackReceiver {

  /* ========== STATE VARIABLES ========== */

  // Vault address
  IGMXVault public vault;
  // GMX role store address
  IRoleStore public roleStore;

  /* ========== MODIFIERS ========== */

  modifier onlyController() {
    if (!roleStore.hasRole(msg.sender, keccak256(abi.encode("CONTROLLER")))) {
      revert Errors.InvalidCallbackHandler();
    } else {
      _;
    }
  }

  /* ========== CONSTRUCTOR ========== */

  /**
    * @dev Initialize callback contract with associated vault address
    * @param _vault Address of vault contract
  */
  constructor (address _vault) {
    vault = IGMXVault(_vault);
    roleStore = IRoleStore(vault.store().roleStore);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * @dev Process vault after successful deposit execution from GMX
    * @notice Callback function for GMX handler to call
    * @param depositKey bytes32 depositKey hash of deposit created
    * @param depositProps IDeposit.Props
    * @param eventData IEvent.Props
  */
  function afterDepositExecution(
    bytes32 depositKey,
    IDeposit.Props memory depositProps,
    IEvent.Props memory eventData
  ) external onlyController {
    GMXTypes.Store memory _store = vault.store();

    if (
      _store.status == GMXTypes.Status.Deposit &&
      _store.depositCache.depositKey == depositKey
    ) {
      vault.processDeposit();
    } else if (
      _store.status == GMXTypes.Status.Rebalance_Add &&
      _store.rebalanceCache.depositKey == depositKey
    ) {
      vault.processRebalanceAdd();
    } else if (
      _store.status == GMXTypes.Status.Compound &&
      _store.compoundCache.depositKey == depositKey
    ) {
      vault.processCompound();
    } else if (
      _store.status == GMXTypes.Status.Withdraw_Failed &&
      _store.withdrawCache.depositKey == depositKey
    ) {
      vault.processWithdrawFailureLiquidityAdded();
    } else {
      revert Errors.NotAllowedInCurrentVaultStatus();
    }
  }

  /**
    * @dev Process vault after deposit cancellation from GMX
    * @notice Callback function for GMX handler to call
    * @notice Should never be called
    * @param depositKey bytes32 depositKey hash of deposit created
    * @param depositProps IDeposit.Props
    * @param eventData IEvent.Props
  */
  function afterDepositCancellation(
    bytes32 depositKey,
    IDeposit.Props memory depositProps,
    IEvent.Props memory eventData
  ) external onlyController {
    GMXTypes.Store memory _store = vault.store();

    if (_store.status == GMXTypes.Status.Deposit) {
      if (_store.depositCache.depositKey == depositKey)
        vault.processDepositCancellation();
    } else if (_store.status == GMXTypes.Status.Rebalance_Add) {
      if (_store.rebalanceCache.depositKey == depositKey)
        vault.processRebalanceAddCancellation();
    } else if (_store.status == GMXTypes.Status.Compound) {
      if (_store.compoundCache.depositKey == depositKey)
        vault.processCompoundCancellation();
    } else {
      revert Errors.DepositCancellationCallback();
    }
  }

  /**
    * @dev Process vault after successful withdrawal execution from GMX
    * @notice Callback function for GMX handler to call
    * @param withdrawKey bytes32 depositKey hash of withdrawal created
    * @param withdrawProps IWithdrawal.Props
    * @param eventData IEvent.Props
  */
  function afterWithdrawalExecution(
    bytes32 withdrawKey,
    IWithdrawal.Props memory withdrawProps,
    IEvent.Props memory eventData
  ) external onlyController {
    GMXTypes.Store memory _store = vault.store();

    if (
      _store.status == GMXTypes.Status.Withdraw &&
      _store.withdrawCache.withdrawKey == withdrawKey
    ) {
      vault.processWithdraw();
    } else if (
      _store.status == GMXTypes.Status.Rebalance_Remove &&
      _store.rebalanceCache.withdrawKey == withdrawKey
    ) {
      vault.processRebalanceRemove();
    } else if (
      _store.status == GMXTypes.Status.Deposit_Failed &&
      _store.depositCache.withdrawKey == withdrawKey
    ) {
      vault.processDepositFailureLiquidityWithdrawal();
    } else {
      revert Errors.NotAllowedInCurrentVaultStatus();
    }
  }

  /**
    * @dev Process vault after withdrawal cancellation from GMX
    * @notice Callback function for GMX handler to call
    * @notice Should never be called
    * @param withdrawKey bytes32 withdrawalKey hash of withdrawal created
    * @param withdrawProps IWithdrawal.Props
    * @param eventData IEvent.Props
  */
  function afterWithdrawalCancellation(
    bytes32 withdrawKey,
    IWithdrawal.Props memory withdrawProps,
    IEvent.Props memory eventData
  ) external onlyController {
    GMXTypes.Store memory _store = vault.store();

    if (_store.status == GMXTypes.Status.Withdraw) {
      if (_store.withdrawCache.withdrawKey == withdrawKey)
        vault.processWithdrawCancellation();
    } else if (_store.status == GMXTypes.Status.Rebalance_Remove) {
      if (_store.rebalanceCache.withdrawKey == withdrawKey)
        vault.processRebalanceRemoveCancellation();
    } else {
      revert Errors.WithdrawalCancellationCallback();
    }
  }
}

