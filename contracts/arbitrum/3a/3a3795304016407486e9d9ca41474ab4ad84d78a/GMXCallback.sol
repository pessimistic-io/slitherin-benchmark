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

contract GMXCallback is IDepositCallbackReceiver, IWithdrawalCallbackReceiver {

  /* ========== EVENTS ========== */

  event DepositCancellation();
  event WithdrawalCancellation();

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

    if (_store.status == GMXTypes.Status.Mint) {
      if (_store.depositCache.depositKey == depositKey)
        vault.processMint();
    } else if (_store.status == GMXTypes.Status.Rebalance_Add_Add_Liquidity) {
      if (_store.rebalanceAddCache.depositKey == depositKey)
        vault.processRebalanceAdd();
    } else if (_store.status == GMXTypes.Status.Compound_Liquidity_Added) {
      if (_store.compoundCache.depositKey == depositKey)
        vault.processCompoundAdded();
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
    emit DepositCancellation();
    revert Errors.DepositCancellationCallback();
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

    if (_store.status == GMXTypes.Status.Swap_For_Repay) {
      if (_store.withdrawCache.withdrawKey == withdrawKey)
        vault.processSwapForRepay();
    } else if (_store.status == GMXTypes.Status.Rebalance_Remove_Swap_For_Repay) {
      if (_store.rebalanceRemoveCache.withdrawKey == withdrawKey)
        vault.processRebalanceRemoveSwapForRepay();
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
    emit WithdrawalCancellation();
    revert Errors.WithdrawalCancellationCallback();
  }
}

