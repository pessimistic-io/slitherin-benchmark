// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "./IGMXDeposit.sol";
import "./IGMXEvent.sol";

// @title IDepositCallbackReceiver
// @dev interface for a deposit callback contract
interface IDepositCallbackReceiver {
  // @dev called after a deposit execution
  // @param key the key of the deposit
  // @param deposit the deposit that was executed
  function afterDepositExecution(
    bytes32 key,
    IGMXDeposit.Props memory deposit,
    IGMXEvent.Props memory eventData
  ) external;

  // @dev called after a deposit cancellation
  // @param key the key of the deposit
  // @param deposit the deposit that was cancelled
  function afterDepositCancellation(
    bytes32 key,
    IGMXDeposit.Props memory deposit,
    IGMXEvent.Props memory eventData
  ) external;
}
