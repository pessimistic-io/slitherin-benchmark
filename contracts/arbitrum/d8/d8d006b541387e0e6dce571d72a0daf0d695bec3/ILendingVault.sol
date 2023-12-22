// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface ILendingVault {
  function lend(uint256 leverage) external returns (bool);

  function repayDebt(uint256 loan, uint256 _amountPaid) external returns (bool);

  function rewardSplit() external view returns (uint256);

  function allocateDebt(uint256 amount) external;

  function totalDebt() external view returns (uint256);

  function totalAssets() external view returns (uint256);

  function balanceOfDAI() external view returns (uint256);
}
