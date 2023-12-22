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

/**
  * @title GMXCallback
  * @author Steadefi
  * @notice The GMX callback handler for Steadefi leveraged vaults
*/
contract GMXCallback is IDepositCallbackReceiver, IWithdrawalCallbackReceiver {

  /* ==================== STATE VARIABLES ==================== */

  // Address of the vault this callback handler is for
  IGMXVault public vault;
  // GMX role store address
  IRoleStore public roleStore;

  /* ======================= MODIFIERS ======================= */

  // Allow only GMX controllers
  modifier onlyController() {
    if (!roleStore.hasRole(msg.sender, keccak256(abi.encode("CONTROLLER")))) {
      revert Errors.InvalidCallbackHandler();
    } else {
      _;
    }
  }

  /* ====================== CONSTRUCTOR ====================== */

  /**
    * @notice Initialize callback contract with associated vault address
    * @param _vault Address of vault
  */
  constructor (address _vault) {
    vault = IGMXVault(_vault);
    roleStore = IRoleStore(vault.store().roleStore);
  }

  /* ================== MUTATIVE FUNCTIONS =================== */

  /**
    * @notice Process vault after successful deposit execution from GMX
    * @dev Callback function for GMX handler to call
    * @param depositKey bytes32 deposit key from GMX
    * @param eventData IEvent.Props
  */
  function afterDepositExecution(
    bytes32 depositKey,
    IDeposit.Props memory /* depositProps */,
    IEvent.Props memory eventData
  ) external onlyController {
    GMXTypes.Store memory _store = vault.store();

    uint256 _lpAmtReceived = eventData.uintItems.items[0].value;

    if (
      _store.status == GMXTypes.Status.Deposit &&
      _store.depositCache.depositKey == depositKey
    ) {
      vault.processDeposit(_lpAmtReceived);
    } else if (
      _store.status == GMXTypes.Status.Rebalance_Add &&
      _store.rebalanceCache.depositKey == depositKey
    ) {
      vault.processRebalanceAdd(_lpAmtReceived);
    } else if (
      _store.status == GMXTypes.Status.Compound &&
      _store.compoundCache.depositKey == depositKey
    ) {
      vault.processCompound(_lpAmtReceived);
    } else if (
      _store.status == GMXTypes.Status.Withdraw_Failed &&
      _store.withdrawCache.depositKey == depositKey
    ) {
      vault.processWithdrawFailureLiquidityAdded(_lpAmtReceived);
    } else if (_store.status == GMXTypes.Status.Resume) {
      // This if block is to catch the Deposit callback after an
      // emergencyResume() to set the vault status to Open
      vault.processEmergencyResume(_lpAmtReceived);
    }
  }

  /**
    * @notice Process vault after deposit cancellation from GMX
    * @dev Callback function for GMX handler to call
    * @param depositKey bytes32 deposit key from GMX
  */
  function afterDepositCancellation(
    bytes32 depositKey,
    IDeposit.Props memory /* depositProps */,
    IEvent.Props memory /* eventData */
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
    } else if (_store.status == GMXTypes.Status.Resume) {
        vault.processEmergencyResumeCancellation();
    } else {
      revert Errors.DepositCancellationCallback();
    }
  }

  /**
    * @notice Process vault after successful withdrawal execution from GMX
    * @dev Callback function for GMX handler to call
    * @param withdrawKey bytes32 withdraw key from GMX
    * @param eventData IEvent.Props
  */
  function afterWithdrawalExecution(
    bytes32 withdrawKey,
    IWithdrawal.Props memory /* withdrawProps */,
    IEvent.Props memory eventData
  ) external onlyController {
    GMXTypes.Store memory _store = vault.store();

    uint256 _tokenAReceived = eventData.uintItems.items[0].value;
    uint256 _tokenBReceived = eventData.uintItems.items[1].value;

    if (
      _store.status == GMXTypes.Status.Withdraw &&
      _store.withdrawCache.withdrawKey == withdrawKey
    ) {
      vault.processWithdraw(_tokenAReceived, _tokenBReceived);
    } else if (
      _store.status == GMXTypes.Status.Rebalance_Remove &&
      _store.rebalanceCache.withdrawKey == withdrawKey
    ) {
      vault.processRebalanceRemove(_tokenAReceived, _tokenBReceived);
    } else if (
      _store.status == GMXTypes.Status.Deposit_Failed &&
      _store.depositCache.withdrawKey == withdrawKey
    ) {
      vault.processDepositFailureLiquidityWithdrawal(_tokenAReceived, _tokenBReceived);
    } else if (
      _store.status == GMXTypes.Status.Paused
    ) {
      vault.processEmergencyRepay(_tokenAReceived, _tokenBReceived);
    }
  }

  /**
    * @notice Process vault after withdrawal cancellation from GMX
    * @dev Callback function for GMX handler to call
    * @param withdrawKey bytes32 withdraw key from GMX
  */
  function afterWithdrawalCancellation(
    bytes32 withdrawKey,
    IWithdrawal.Props memory /* withdrawProps */,
    IEvent.Props memory /* eventData */
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

