// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ManagerAction.sol";

interface IGMXPerpetualDEXLongManager {
  function debtInfo() external view returns (uint256);
  function lpTokenAmt() external view returns (uint256);
  function currentTokenWeight(address _token) external view returns (uint256);
  function currentTokenWeights() external view returns (address[] memory, uint256[] memory);
  function assetInfo() external view returns (address[] memory, uint256[] memory);
  function glpManager() external view returns (address);
  function work(
    ManagerAction _action,
    uint256 _lpAmt,
    uint256 _borrowTokenAAmt,
    uint256 _repayTokenAAmt
  ) external;
  function compound(address[] memory _rewardTrackers) external;
  function tokenLendingPool() external view returns (address);
}

