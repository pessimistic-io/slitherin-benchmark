// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IDeposit } from "./IDeposit.sol";
import { IWithdrawal } from "./IWithdrawal.sol";
import { IEvent } from "./IEvent.sol";
import { IOrder } from "./IOrder.sol";
import { IDepositCallbackReceiver } from "./IDepositCallbackReceiver.sol";
import { IWithdrawalCallbackReceiver } from "./IWithdrawalCallbackReceiver.sol";
import { IOrderCallbackReceiver } from "./IOrderCallbackReceiver.sol";
import { IRoleStore } from "./IRoleStore.sol";
import { IGMXVault } from "./IGMXVault.sol";
import { Errors } from "./Errors.sol";
import { GMXTypes } from "./GMXTypes.sol";

contract GMXCallback is IDepositCallbackReceiver, IWithdrawalCallbackReceiver, IOrderCallbackReceiver {

  /* ========== STATE VARIABLES ========== */

  // Vault address
  IGMXVault public vault;
  // GMX role store address
  IRoleStore public roleStore;

  // TEMP
  address public handler;
  uint256 public timestamp;
  bytes32 public key;

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

  function viewStatus() external view returns (GMXTypes.Status) {
    return vault.store().status;
  }

  function viewStore() external view returns (GMXTypes.Store memory) {
    return vault.store();
  }

  /**
    * @dev Process vault after successful deposit execution from GMX
    * @notice Callback function for GMX handler to call or approved keepers
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

    key = depositKey;
    handler = msg.sender;
    timestamp = block.timestamp;

    _afterDepositCallbackChecks(
      depositKey,
      depositProps,
      eventData
    );

    if (_store.status == GMXTypes.Status.Mint) {
      vault.processMint(depositKey);
    } else if (_store.status == GMXTypes.Status.Rebalance_Add_Add_Liquidity) {
      vault.processRebalanceAdd(depositKey);
    } else if (_store.status == GMXTypes.Status.Compound_Liquidity_Added) {
      vault.processCompoundAdded(depositKey);
    }
  }

  /**
    * @dev Process vault after deposit cancellation from GMX
    * @notice Callback function for GMX handler to call or approved keepers
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

    key = depositKey;
    handler = msg.sender;
    timestamp = block.timestamp;

    _afterDepositCallbackChecks(
      depositKey,
      depositProps,
      eventData
    );

    // TODO
    // GMXDeposit.afterDepositCancellation(_store, depositKey);
  }

  /**
    * @dev Process vault after successful withdrawal execution from GMX
    * @notice Callback function for GMX handler to call or approved keepers
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

    key = withdrawKey;
    handler = msg.sender;
    timestamp = block.timestamp;

    _afterWithdrawalCallbackChecks(
      withdrawKey,
      withdrawProps,
      eventData
    );

    if (_store.status == GMXTypes.Status.Swap_For_Repay) {
      vault.processSwapForRepay(withdrawKey);
    } else if (_store.status == GMXTypes.Status.Rebalance_Remove_Swap_For_Repay) {
      vault.processRebalanceRemoveSwapForRepay(withdrawKey);
    }
  }

  /**
    * @dev Process vault after withdrawal cancellation from GMX
    * @notice Callback function for GMX handler to call or approved keepers
    * @param withdrawKey bytes32 withdrawalKey hash of withdrawal created
    * @param withdrawProps IWithdrawal.Props
    * @param eventData IEvent.Props
  */
  function afterWithdrawalCancellation(
    bytes32 withdrawKey,
    IWithdrawal.Props memory withdrawProps,
    IEvent.Props memory eventData
  ) external {
    GMXTypes.Store memory _store = vault.store();

    key = withdrawKey;
    handler = msg.sender;
    timestamp = block.timestamp;

    _afterWithdrawalCallbackChecks(
      withdrawKey,
      withdrawProps,
      eventData
    );

    // TODO
    // GMXWithdraw.afterWithdrawalCancellation(_store, withdrawKey);
  }

  /**
    * @dev Process vault after successful order execution from GMX
    * @notice Callback function for GMX handler to call or approved keepers
    * @param orderKey bytes32 orderKey hash of order created
    * @param orderProps IOrder.Props
    * @param eventData IEvent.Props
  */
  function afterOrderExecution(
    bytes32 orderKey,
    IOrder.Props memory orderProps,
    IEvent.Props memory eventData
  ) external {
    GMXTypes.Store memory _store = vault.store();

    key = orderKey;
    handler = msg.sender;
    timestamp = block.timestamp;

    _afterOrderCallbackChecks(
      orderKey,
      orderProps,
      eventData
    );

    if (_store.status == GMXTypes.Status.Repay) {
      vault.processRepay(_store.withdrawCache.withdrawKey, orderKey);
    } else if (_store.status == GMXTypes.Status.Burn) {
      vault.processBurn(_store.withdrawCache.withdrawKey, orderKey);
    } else if (_store.status == GMXTypes.Status.Rebalance_Remove_Repay) {
      vault.processBurn(_store.rebalanceRemoveCache.withdrawKey, orderKey);
    } else if (_store.status == GMXTypes.Status.Compound_Add_Liquidity) {
      vault.processCompoundAdd(orderKey);
    }
  }

  /**
    * @dev Process vault after order cancellation from GMX
    * @notice Callback function for GMX handler to call or approved keepers
    * @param orderKey bytes32 orderKey hash of order created
    * @param orderProps IOrder.Props
    * @param eventData IEvent.Props
  */
  function afterOrderCancellation(
    bytes32 orderKey,
    IOrder.Props memory orderProps,
    IEvent.Props memory eventData
  ) external {
    GMXTypes.Store memory _store = vault.store();

    key = orderKey;
    handler = msg.sender;
    timestamp = block.timestamp;

    _afterOrderCallbackChecks(
      orderKey,
      orderProps,
      eventData
    );

    // TODO
    // GMXWithdraw.afterOrderCancellation(_store, orderKey, order, eventData);
  }

  /**
    * @dev Process vault after order is considered frozen from GMX
    * @notice Callback function for GMX handler to call or approved keepers
    * @param orderKey bytes32 orderKey hash of order created
    * @param orderProps IOrder.Props
    * @param eventData IEvent.Props
  */
  function afterOrderFrozen(
    bytes32 orderKey,
    IOrder.Props memory orderProps,
    IEvent.Props memory eventData
  ) external {
    GMXTypes.Store memory _store = vault.store();

    key = orderKey;
    handler = msg.sender;
    timestamp = block.timestamp;

    _afterOrderCallbackChecks(
      orderKey,
      orderProps,
      eventData
    );

    // TODO
    // GMXWithdraw.afterOrderFrozen(_store, orderKey, order, eventData);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
    * @dev Checks after deposit callbacks from GMX handler
    * @param depositKey bytes32 depositKey hash of deposit created
    * @param depositProps IDeposit.Props
    * @param eventData IEvent.Props
  */
  function _afterDepositCallbackChecks(
    bytes32 depositKey,
    IDeposit.Props memory depositProps,
    IEvent.Props memory eventData
  ) internal {
    GMXTypes.Store memory _store = vault.store();

    if (
      _store.status != GMXTypes.Status.Mint &&
      _store.status != GMXTypes.Status.Rebalance_Add_Add_Liquidity &&
      _store.status != GMXTypes.Status.Compound_Liquidity_Added
    ) revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @dev Checks after withdrawal callbacks from GMX handler
    * @param withdrawKey bytes32 withdrawKey hash of withdraw created
    * @param withdrawProps IWithdrawal.Props
    * @param eventData IEvent.Props
  */
  function _afterWithdrawalCallbackChecks(
    bytes32 withdrawKey,
    IWithdrawal.Props memory withdrawProps,
    IEvent.Props memory eventData
  ) internal view {
    GMXTypes.Store memory _store = vault.store();

    if (
      _store.status != GMXTypes.Status.Swap_For_Repay &&
      _store.status != GMXTypes.Status.Rebalance_Remove_Remove_Liquidity
    ) revert Errors.NotAllowedInCurrentVaultStatus();
  }

  /**
    * @dev Checks after order callbacks from GMX handler
    * @param orderKey bytes32 orderKey hash of order created
    * @param orderProps IOrder.Props
    * @param eventData IEvent.Props
  */
  function _afterOrderCallbackChecks(
    bytes32 orderKey,
    IOrder.Props memory orderProps,
    IEvent.Props memory eventData
  ) internal view {
    GMXTypes.Store memory _store = vault.store();

    if (
      _store.status != GMXTypes.Status.Repay &&
      _store.status != GMXTypes.Status.Swap_For_Withdraw &&
      _store.status != GMXTypes.Status.Rebalance_Remove_Swap_For_Repay &&
      _store.status != GMXTypes.Status.Compound_Add_Liquidity
    ) revert Errors.NotAllowedInCurrentVaultStatus();
  }
}

