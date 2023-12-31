// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { GMXTypes } from "./GMXTypes.sol";

interface IGMXVault {
  function store() external view returns (GMXTypes.Store memory);
  function isTokenWhitelisted(address token) external view returns (bool);

  function deposit(GMXTypes.DepositParams memory dp) external payable;
  function depositNative(GMXTypes.DepositParams memory dp) external payable;
  function processDeposit() external;
  function processDepositCancellation() external;
  function processDepositFailure(
    uint256 slippage,
    uint256 executionFee
  ) external payable;
  function processDepositFailureLiquidityWithdrawal() external;

  function withdraw(GMXTypes.WithdrawParams memory wp) external payable;
  function processWithdraw() external;
  function processWithdrawCancellation() external;
  function processWithdrawFailure(
    uint256 slippage,
    uint256 executionFee
  ) external payable;
  function processWithdrawFailureLiquidityAdded() external;

  function emergencyWithdraw(uint256 shareAmt) external;
  function mintMgmtFee() external;

  function compound(GMXTypes.CompoundParams memory cp) external payable;
  function processCompound() external;
  function processCompoundCancellation() external;

  function rebalanceAdd(
    GMXTypes.RebalanceAddParams memory rap
  ) external payable;
  function processRebalanceAdd() external;
  function processRebalanceAddCancellation() external;

  function rebalanceRemove(
    GMXTypes.RebalanceRemoveParams memory rrp
  ) external payable;
  function processRebalanceRemove() external;
  function processRebalanceRemoveCancellation() external;

  function emergencyShutdown() external payable;
  function emergencyClose() external;
  function emergencyResume() external payable;

  function pause() external;
  function unpause() external;

  function updateKeeper(address keeper, bool approval) external;
  function updateTreasury(address treasury) external;
  function updateSwapRouter(address swapRouter) external;
  function updateCallback(address callback) external;
  function updateMgmtFeePerSecond(uint256 mgmtFeePerSecond) external;
  function updatePerformanceFee(uint256 performanceFee) external;
  function mint(address to, uint256 amt) external;
  function burn(address to, uint256 amt) external;

  function updateParameterLimits(
    uint256 debtRatioStepThreshold,
    uint256 debtRatioUpperLimit,
    uint256 debtRatioLowerLimit,
    int256 deltaUpperLimit,
    int256 deltaLowerLimit
  ) external;

  function updateMinSlippage(uint256 minSlippage) external;
  function updateMinExecutionFee(uint256 minExecutionFee) external;
}

