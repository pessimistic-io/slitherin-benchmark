// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IWNT } from "./IWNT.sol";
import { IDeposit } from "./IDeposit.sol";
import { IWithdrawal } from "./IWithdrawal.sol";
import { IEvent } from "./IEvent.sol";
import { IOrder } from "./IOrder.sol";
import { IDepositCallbackReceiver } from "./IDepositCallbackReceiver.sol";
import { IWithdrawalCallbackReceiver } from "./IWithdrawalCallbackReceiver.sol";
import { IOrderCallbackReceiver } from "./IOrderCallbackReceiver.sol";

import { IGMXTest } from "./IGMXTest.sol";

contract GMXCallbackTest is IDepositCallbackReceiver, IWithdrawalCallbackReceiver, IOrderCallbackReceiver {

  address public WNT = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

  /* ========== STATE VARIABLES ========== */

  // Vault address
  IGMXTest public vault;
  bytes32 public _depositKey;
  bytes32 public _withdrawKey;
  bytes32 public _orderKey;
  address public depositHandler;
  address public withdrawHandler;
  address public orderHandler;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @dev Initialize callback contract with associated vault address
    * @param _vault Address of vault contract
  */
  constructor (address _vault) {
    vault = IGMXTest(_vault);
  }

  function afterDepositExecution(
    bytes32 depositKey,
    IDeposit.Props memory depositProps,
    IEvent.Props memory eventData
  ) external {
    _depositKey = depositKey;
    depositHandler = msg.sender;

    vault.postDeposit();
  }

  function afterDepositCancellation(
    bytes32 depositKey,
    IDeposit.Props memory depositProps,
    IEvent.Props memory eventData
  ) external {
    _depositKey = depositKey;
    depositHandler = msg.sender;

    vault.postDepositCancel();
  }

  function afterWithdrawalExecution(
    bytes32 withdrawKey,
    IWithdrawal.Props memory withdrawProps,
    IEvent.Props memory eventData
  ) external {
    _withdrawKey = withdrawKey;
    withdrawHandler = msg.sender;

    vault.postWithdraw();
  }

  function afterWithdrawalCancellation(
    bytes32 withdrawKey,
    IWithdrawal.Props memory withdrawProps,
    IEvent.Props memory eventData
  ) external {
    _withdrawKey = withdrawKey;
    withdrawHandler = msg.sender;

    vault.postWithdrawCancel();
  }

  function afterOrderExecution(
    bytes32 orderKey,
    IOrder.Props memory orderProps,
    IEvent.Props memory eventData
  ) external {
    _orderKey = orderKey;
    orderHandler = msg.sender;

    vault.postSwap();
  }

  function afterOrderCancellation(
    bytes32 orderKey,
    IOrder.Props memory orderProps,
    IEvent.Props memory eventData
  ) external {
    _orderKey = orderKey;
    orderHandler = msg.sender;

    // vault.postSwap();
  }

  function afterOrderFrozen(
    bytes32 orderKey,
    IOrder.Props memory orderProps,
    IEvent.Props memory eventData
  ) external {
    _orderKey = orderKey;
    orderHandler = msg.sender;

    // vault.postSwap();
  }

  function triggerSwapGMX() external {
    vault.swapGMX();
  }


}

