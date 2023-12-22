// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IDeposit } from "./IDeposit.sol";
import { IWithdrawal } from "./IWithdrawal.sol";
import { IEvent } from "./IEvent.sol";
import { IOrder } from "./IOrder.sol";
import { IDepositCallbackReceiver } from "./IDepositCallbackReceiver.sol";
import { IWithdrawalCallbackReceiver } from "./IWithdrawalCallbackReceiver.sol";
import { IOrderCallbackReceiver } from "./IOrderCallbackReceiver.sol";

interface IGMXTest {
  function postDeposit() payable external;
}

contract GMXCallbackTest is IDepositCallbackReceiver {

  /* ========== STATE VARIABLES ========== */

  // Vault address
  IGMXTest public vault;
  bytes32 _depositKey;
  address handler;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @dev Initialize callback contract with associated vault address
    * @param _vault Address of vault contract
  */
  constructor (address _vault) {
    vault = IGMXTest(_vault);
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
  ) external {

    _depositKey = depositKey;
    handler = msg.sender;

    vault.postDeposit();
  }

  function afterDepositCancellation(
    bytes32 depositKey,
    IDeposit.Props memory depositProps,
    IEvent.Props memory eventData
  ) external {

    _depositKey = depositKey;
    handler = msg.sender;
  }

  receive() external payable {
    // require(msg.sender == WNT, "msg.sender != WNT");
  }

}

