// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IGMXDeposit } from "./IGMXDeposit.sol";
import { IGMXWithdrawal } from "./IGMXWithdrawal.sol";
import { IGMXEvent } from "./IGMXEvent.sol";
import { IGMXOrder } from "./IGMXOrder.sol";
import { IDepositCallbackReceiver } from "./IDepositCallbackReceiver.sol";
import { IWithdrawalCallbackReceiver } from "./IWithdrawalCallbackReceiver.sol";
import { IOrderCallbackReceiver } from "./IOrderCallbackReceiver.sol";
import { IGMXVault } from "./IGMXVault.sol";
import { Errors } from "./Errors.sol";
import { GMXTypes } from "./GMXTypes.sol";

contract GMXCallback is IDepositCallbackReceiver, IWithdrawalCallbackReceiver, IOrderCallbackReceiver {

  /* ========== STATE VARIABLES ========== */

  // Vault address
  IGMXVault public vault;
  // TEMP TODO
  IGMXDeposit.Props public _depositProps;
  // TEMP TODO
  IGMXWithdrawal.Props public _withdrawProps;
  // TEMP TODO
  IGMXOrder.Props public _orderProps;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @dev Initialize callback contract with associated vault address
    * @param _vault Address of vault contract
  */
  constructor (address _vault) {
    vault = IGMXVault(_vault);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * @dev Process vault after successful deposit execution from GMX
    * @notice Callback function for GMX handler to call or approved keepers
    * @param depositKey bytes32 depositKey hash of deposit created
    * @param depositProps IGMXDeposit.Props
    * @param eventData IGMXEvent.Props
  */
  function afterDepositExecution(
    // GMXTypes.Store storage _store,
    bytes32 depositKey,
    IGMXDeposit.Props memory depositProps,
    IGMXEvent.Props memory eventData
  ) external {

    GMXTypes.Store memory _store = vault.store();

    _depositProps = depositProps;
    // _eventData = eventData;

    _afterDepositCallbackChecks(
      msg.sender,
      depositKey,
      depositProps,
      eventData
    );

    if (_store.status == GMXTypes.Status.Mint) {
      // GMXDeposit.processMint(_store, depositKey);
      vault.processMint(depositKey);
    } else if (_store.status == GMXTypes.Status.Rebalance_Add_Add_Liquidity) {
      // GMXRebalance.processRebalanceAdd(_store, depositKey);
      vault.processRebalanceAdd(depositKey);
    }
  }

  /**
    * @dev Process vault after deposit cancellation from GMX
    * @notice Callback function for GMX handler to call or approved keepers
    * @param depositKey bytes32 depositKey hash of deposit created
    * @param depositProps IGMXDeposit.Props
    * @param eventData IGMXEvent.Props
  */
  function afterDepositCancellation(
    // GMXTypes.Store storage _store,
    bytes32 depositKey,
    IGMXDeposit.Props memory depositProps,
    IGMXEvent.Props memory eventData
  ) external {
    GMXTypes.Store memory _store = vault.store();

    _depositProps = depositProps;
    // _eventData = eventData;

    _afterDepositCallbackChecks(
      msg.sender,
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
    * @param withdrawProps IGMXWithdrawal.Props
    * @param eventData IGMXEvent.Props
  */
  function afterWithdrawalExecution(
    // GMXTypes.Store storage _store,
    bytes32 withdrawKey,
    IGMXWithdrawal.Props memory withdrawProps,
    IGMXEvent.Props memory eventData
  ) external {
    GMXTypes.Store memory _store = vault.store();

    _withdrawProps = withdrawProps;
    // _eventData = eventData;

    _afterWithdrawalCallbackChecks(
      msg.sender,
      withdrawKey,
      withdrawProps,
      eventData
    );

    if (_store.status == GMXTypes.Status.Swap_For_Repay) {
      // GMXWithdraw.processSwapForRepay(_store, withdrawKey);
      vault.processSwapForRepay(withdrawKey);
    } else if (_store.status == GMXTypes.Status.Rebalance_Remove_Swap_For_Repay) {
      // GMXRebalance.processRebalanceRemoveSwapForRepay(_store, withdrawKey);
      vault.processRebalanceRemoveSwapForRepay(withdrawKey);
    }
  }

  /**
    * @dev Process vault after withdrawal cancellation from GMX
    * @notice Callback function for GMX handler to call or approved keepers
    * @param withdrawKey bytes32 withdrawalKey hash of withdrawal created
    * @param withdrawProps IGMXWithdrawal.Props
    * @param eventData IGMXEvent.Props
  */
  function afterWithdrawalCancellation(
    // GMXTypes.Store storage _store,
    bytes32 withdrawKey,
    IGMXWithdrawal.Props memory withdrawProps,
    IGMXEvent.Props memory eventData
  ) external {
    GMXTypes.Store memory _store = vault.store();

    _withdrawProps = withdrawProps;
    // _eventData = eventData;

    _afterWithdrawalCallbackChecks(
      msg.sender,
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
    * @param orderProps IGMXOrder.Props
    * @param eventData IGMXEvent.Props
  */
  function afterOrderExecution(
    // GMXTypes.Store storage _store,
    bytes32 orderKey,
    IGMXOrder.Props memory orderProps,
    IGMXEvent.Props memory eventData
  ) external {
    GMXTypes.Store memory _store = vault.store();

    _orderProps = orderProps;
    // _eventData = eventData;

    _afterOrderCallbackChecks(
      msg.sender,
      orderKey,
      orderProps,
      eventData
    );

    if (_store.status == GMXTypes.Status.Repay) {
      // GMXWithdraw.processRepay(_store, _store.withdrawCache.withdrawKey, orderKey);
      vault.processRepay(_store.withdrawCache.withdrawKey, orderKey);
    } else if (_store.status == GMXTypes.Status.Burn) {
      // GMXWithdraw.processBurn(_store, _store.withdrawCache.withdrawKey, orderKey);
      vault.processBurn(_store.withdrawCache.withdrawKey, orderKey);
    } else if (_store.status == GMXTypes.Status.Rebalance_Remove_Repay) {
      // GMXWithdraw.processBurn(_store, _store.rebalanceRemoveCache.withdrawKey, orderKey);
      vault.processBurn(_store.rebalanceRemoveCache.withdrawKey, orderKey);
    }
  }

  /**
    * @dev Process vault after order cancellation from GMX
    * @notice Callback function for GMX handler to call or approved keepers
    * @param orderKey bytes32 orderKey hash of order created
    * @param orderProps IGMXOrder.Props
    * @param eventData IGMXEvent.Props
  */
  function afterOrderCancellation(
    // GMXTypes.Store storage _store,
    bytes32 orderKey,
    IGMXOrder.Props memory orderProps,
    IGMXEvent.Props memory eventData
  ) external {
    GMXTypes.Store memory _store = vault.store();

    _orderProps = orderProps;
    // _eventData = eventData;

    _afterOrderCallbackChecks(
      msg.sender,
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
    * @param orderProps IGMXOrder.Props
    * @param eventData IGMXEvent.Props
  */
  function afterOrderFrozen(
    // GMXTypes.Store storage _store,
    bytes32 orderKey,
    IGMXOrder.Props memory orderProps,
    IGMXEvent.Props memory eventData
  ) external {
    GMXTypes.Store memory _store = vault.store();

    _orderProps = orderProps;
    // _eventData = eventData;

    _afterOrderCallbackChecks(
      msg.sender,
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
    * @param handler Address of callback handler
    * @param depositKey bytes32 depositKey hash of deposit created
    * @param depositProps IGMXDeposit.Props
    * @param eventData IGMXEvent.Props
  */
  function _afterDepositCallbackChecks(
    address handler,
    bytes32 depositKey,
    IGMXDeposit.Props memory depositProps,
    IGMXEvent.Props memory eventData
  ) internal view {
    GMXTypes.Store memory _store = vault.store();

    if (
      _store.status != GMXTypes.Status.Mint ||
      _store.status != GMXTypes.Status.Rebalance_Add_Add_Liquidity
    ) revert Errors.NotAllowedInCurrentVaultStatus();

    if (handler != _store.depositHandler)
      revert Errors.InvalidCallbackHandler();

    if (_store.status == GMXTypes.Status.Mint) {
      GMXTypes.DepositCache memory _dc = _store.depositCache;

      if (
        depositKey == bytes32(0) ||
        depositKey != _dc.depositKey
      ) revert Errors.InvalidDepositKey();
    }

    if (_store.status == GMXTypes.Status.Rebalance_Add_Add_Liquidity) {
      GMXTypes.RebalanceAddCache memory _rac = _store.rebalanceAddCache;

      if (
        depositKey == bytes32(0) ||
        depositKey != _rac.depositKey
      ) revert Errors.InvalidDepositKey();
    }
  }

  /**
    * @dev Checks after withdrawal callbacks from GMX handler
    * @param handler Address of callback handler
    * @param withdrawKey bytes32 withdrawKey hash of withdraw created
    * @param withdrawProps IGMXWithdrawal.Props
    * @param eventData IGMXEvent.Props
  */
  function _afterWithdrawalCallbackChecks(
    address handler,
    bytes32 withdrawKey,
    IGMXWithdrawal.Props memory withdrawProps,
    IGMXEvent.Props memory eventData
  ) internal view {
    GMXTypes.Store memory _store = vault.store();

    if (
      _store.status != GMXTypes.Status.Swap_For_Repay ||
      _store.status != GMXTypes.Status.Rebalance_Remove_Remove_Liquidity
    ) revert Errors.NotAllowedInCurrentVaultStatus();

    if (handler != _store.withdrawalHandler)
      revert Errors.InvalidCallbackHandler();

    if (_store.status == GMXTypes.Status.Swap_For_Repay) {
      GMXTypes.WithdrawCache memory _wc = _store.withdrawCache;

      if (
        withdrawKey == bytes32(0) ||
        withdrawKey != _wc.withdrawKey
      ) revert Errors.InvalidDepositKey();
    }

    if (_store.status == GMXTypes.Status.Rebalance_Remove_Remove_Liquidity) {
      GMXTypes.RebalanceRemoveCache memory _rrc =
        _store.rebalanceRemoveCache;

      if (
        withdrawKey == bytes32(0) ||
        withdrawKey != _rrc.withdrawKey
      ) revert Errors.InvalidDepositKey();
    }
  }

  /**
    * @dev Checks after order callbacks from GMX handler
    * @param handler Address of callback handler
    * @param orderKey bytes32 orderKey hash of order created
    * @param orderProps IGMXOrder.Props
    * @param eventData IGMXEvent.Props
  */
  function _afterOrderCallbackChecks(
    address handler,
    bytes32 orderKey,
    IGMXOrder.Props memory orderProps,
    IGMXEvent.Props memory eventData
  ) internal view {
    GMXTypes.Store memory _store = vault.store();

    if (
      _store.status != GMXTypes.Status.Repay ||
      _store.status != GMXTypes.Status.Swap_For_Withdraw ||
      _store.status != GMXTypes.Status.Rebalance_Remove_Swap_For_Repay
    ) revert Errors.NotAllowedInCurrentVaultStatus();

    if (handler != _store.orderHandler)
      revert Errors.InvalidCallbackHandler();

    if (_store.status == GMXTypes.Status.Repay) {
      GMXTypes.WithdrawCache memory _wc = _store.withdrawCache;

      if (
        orderKey == bytes32(0) ||
        orderKey != _wc.withdrawParams.swapForRepayParams.orderKey
      ) revert Errors.InvalidDepositKey();
    }

    if (_store.status == GMXTypes.Status.Withdraw) {
      GMXTypes.WithdrawCache memory _wc = _store.withdrawCache;

      if (
        orderKey == bytes32(0) ||
        orderKey != _wc.withdrawParams.swapForWithdrawParams.orderKey
      ) revert Errors.InvalidDepositKey();
    }

    if (_store.status == GMXTypes.Status.Rebalance_Remove_Swap_For_Repay) {
      GMXTypes.RebalanceRemoveCache memory _rrc =
        _store.rebalanceRemoveCache;

      if (
        orderKey == bytes32(0) ||
        orderKey != _rrc.rebalanceRemoveParams.swapForRepayParams.orderKey
      ) revert Errors.InvalidDepositKey();
    }
  }
}

