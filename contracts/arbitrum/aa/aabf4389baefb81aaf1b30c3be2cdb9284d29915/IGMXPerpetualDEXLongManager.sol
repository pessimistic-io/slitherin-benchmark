// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ManagerAction.sol";

interface IGMXPerpetualDEXLongManager {
  struct WorkData {
    address token;
    uint256 lpAmt;
    uint256 borrowUSDCAmt;
    uint256 repayUSDCAmt;
  }

  function debtAmt() external view returns (uint256);
  function lpAmt() external view returns (uint256);
  function work(
    ManagerAction _action,
    WorkData calldata _data
  ) external;
  function lendingPoolUSDC() external view returns (address);
  function stakePool() external view returns (address);
  function compound() external;
  function updateKeeper(address _keeper, bool _approval) external;
}

