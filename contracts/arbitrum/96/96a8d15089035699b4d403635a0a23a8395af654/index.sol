// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface GnosisSafe {
  /// @dev Allows a Module to execute a Safe transaction without any further confirmations.
  /// @param to Destination address of module transaction.
  /// @param value Ether value of module transaction.
  /// @param data Data payload of module transaction.
  /// @param operation Operation type of module transaction.
  function execTransactionFromModule(
    address to,
    uint256 value,
    bytes calldata data,
    uint256 operation
  ) external returns (bool success);
}

interface AlowanceModule {
  struct Allowance {
    uint96 amount;
    uint96 spent;
    uint16 resetTimeMin; // Maximum reset time span is 65k minutes
    uint32 lastResetMin;
    uint16 nonce;
  }

  function executeAllowanceTransfer(
    GnosisSafe safe,
    address token,
    address payable to,
    uint96 amount,
    address paymentToken,
    uint96 payment,
    address delegate,
    bytes memory signature
  ) external;

  function getTokenAllowance(
    address safe,
    address delegate,
    address token
  ) external view returns (uint256[5] memory);
}

