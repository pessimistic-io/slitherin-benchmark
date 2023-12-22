// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ManagerAction.sol";

interface ICamelotYieldFarmManager {
  function assetInfo() external view returns (uint256, uint256);
  function debtInfo() external view returns (uint256, uint256);
  function lpTokenAmt() external view returns (uint256);
  function tokenALendingPool() external view returns (address);
  function tokenBLendingPool() external view returns (address);

  function work(
    ManagerAction _action,
    uint256 _lpAmt,
    uint256 _borrowTokenAAmt,
    uint256 _borrowTokenBAmt,
    uint256 _repayTokenAAmt,
    uint256 _repayTokenBAmt
  ) external;

  function compound(bytes calldata data) external;

  function allocate(bytes calldata data) external;

  function deallocate(bytes calldata data) external;

  function redeem(uint256 amt, uint256 redeemDuration) external;

  function finalizeRedeem() external;
}

