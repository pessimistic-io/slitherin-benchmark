// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IGMXTest {
  function postDeposit() external;
  function postWithdraw() external;
  function postSwap() external;
  function swapGMX() external;
  function postDepositCancel() external;
  function postWithdrawCancel() external;
}

