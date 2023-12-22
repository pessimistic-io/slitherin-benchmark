// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { GMXTypes } from "./GMXTypes.sol";

interface IGMXVault {
  function store() external view returns (GMXTypes.Store memory);
  function isTokenWhitelisted(address token) external view returns (bool);

  function deposit(GMXTypes.DepositParams memory dp) payable external;
  function depositNative(GMXTypes.DepositParams memory dp) payable external;
  function processMint() external;

  function withdraw(GMXTypes.WithdrawParams memory wp) payable external;
  function processSwapForRepay() external;
  function processRepay() external;
  function processBurn() external;

  function emergencyWithdraw(uint256 shareAmt) external;
  function mintMgmtFee() external;

  function compound(GMXTypes.CompoundParams memory cp) payable external;
  function processCompoundAdd() external;
  function processCompoundAdded() external;

  function rebalanceAdd(
    GMXTypes.RebalanceAddParams memory rebalanceAddParams
  ) payable external;
  function processRebalanceAdd() external;

  function rebalanceRemove(
    GMXTypes.RebalanceRemoveParams memory rebalanceRemoveParams
  ) payable external;
  function processRebalanceRemoveSwapForRepay() external;
  function processRebalanceRemoveRepay() external;
  function processRebalanceRemoveAddLiquidity() external;

  function emergencyShutdown() payable external;
  function emergencyRepay(uint256 shareRatio) external;
  function emergencyResume() payable external;

  function pause() external;
  function unpause() external;

  function updateKeeper(address keeper, bool approval) external;
  function updateTreasury(address treasury) external;
  function updateCallback(address callback) external;
  function updateMgmtFeePerSecond(uint256 mgmtFeePerSecond) external;
  function updatePerformanceFee(uint256 performanceFee) external;
  function updateMaxCapacity(uint256 maxCapacity) external;
  function mint(address to, uint256 amt) external;
  function burn(address to, uint256 amt) external;

  function updateParameterLimits(
    uint256 debtRatioStepThreshold,
    uint256 deltaStepThreshold,
    uint256 debtRatioUpperLimit,
    uint256 debtRatioLowerLimit,
    int256 deltaUpperLimit,
    int256 deltaLowerLimit
  ) external;

  function updateMinExecutionFee(uint256 minExecutionFee) external;
}

