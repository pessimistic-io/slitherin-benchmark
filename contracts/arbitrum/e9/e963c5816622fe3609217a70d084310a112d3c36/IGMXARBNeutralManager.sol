// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ManagerAction.sol";

interface IGMXARBNeutralManager {
  struct WorkData {
    address token;
    uint256 lpAmt;
    uint256 borrowWETHAmt;
    uint256 borrowWBTCAmt;
    uint256 borrowUSDCAmt;
    uint256 repayWETHAmt;
    uint256 repayWBTCAmt;
    uint256 repayUSDCAmt;
  }

  function debtAmts() external view returns (uint256, uint256, uint256);
  function debtAmt(address _token) external view returns (uint256);
  function lpAmt() external view returns (uint256);
  function work(
    ManagerAction _action,
    WorkData calldata _workData
  ) external;
  function lendingPoolWETH() external view returns (address);
  function lendingPoolWBTC() external view returns (address);
  function lendingPoolUSDC() external view returns (address);
  function stakePool() external view returns (address);
  function compound() external;
  function updateKeeper(address _keeper, bool _approval) external;
}

