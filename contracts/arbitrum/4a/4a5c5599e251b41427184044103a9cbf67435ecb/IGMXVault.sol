// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { GMXTypes } from "./GMXTypes.sol";

interface IGMXVault {
  function store() external view returns (GMXTypes.Store memory);
  function deposit(GMXTypes.DepositParams memory dp) external payable;
  function depositNative(GMXTypes.DepositParams memory dp) external payable;
  function processDeposit(uint256 lpAmtReceived) external;
  function processDepositCancellation() external;
  function processDepositFailure(uint256 executionFee) external payable;
  function processDepositFailureLiquidityWithdrawal(
    uint256 tokenAReceived,
    uint256 tokenBReceived
  ) external;

  function withdraw(GMXTypes.WithdrawParams memory wp) external payable;
  function processWithdraw(
    uint256 tokenAReceived,
    uint256 tokenBReceived
  ) external;
  function processWithdrawCancellation() external;
  function processWithdrawFailure(uint256 executionFee) external payable;
  function processWithdrawFailureLiquidityAdded(uint256 lpAmtReceived) external;

  function rebalanceAdd(
    GMXTypes.RebalanceAddParams memory rap
  ) external payable;
  function processRebalanceAdd(uint256 lpAmtReceived) external;
  function processRebalanceAddCancellation() external;

  function rebalanceRemove(
    GMXTypes.RebalanceRemoveParams memory rrp
  ) external payable;
  function processRebalanceRemove(
    uint256 tokenAReceived,
    uint256 tokenBReceived
  ) external;
  function processRebalanceRemoveCancellation() external;

  function compound(GMXTypes.CompoundParams memory cp) external payable;
  function processCompound(uint256 lpAmtReceived) external;
  function processCompoundCancellation() external;

  function emergencyPause() external payable;
  function emergencyPauseForce() external payable;
  function processEmergencyPause(
    uint256 tokenAReceived,
    uint256 tokenBReceived
  ) external;
  function emergencyResume() external payable;
  function processEmergencyResume(uint256 lpAmtReceived) external;
  function processEmergencyResumeCancellation() external;
  function emergencyClose() external;
  function emergencyWithdraw(uint256 shareAmt) external;

  function updateBlocklist(address addr, bool blocked) external;
  function updateKeeper(address keeper, bool approval) external;
  function updateTreasury(address treasury) external;
  function updateSwapRouter(address swapRouter) external;
  function updateCallback(address callback) external;
  function updateFeePerSecond(uint256 feePerSecond) external;
  function updateParameterLimits(
    uint256 debtRatioStepThreshold,
    uint256 debtRatioUpperLimit,
    uint256 debtRatioLowerLimit,
    int256 deltaUpperLimit,
    int256 deltaLowerLimit
  ) external;
  function updateMinVaultSlippage(uint256 minVaultSlippage) external;
  function updateLiquiditySlippage(uint256 liquiditySlippage) external;
  function updateSwapSlippage(uint256 swapSlippage) external;
  function updateCallbackGasLimit(uint256 callbackGasLimit) external;
  function updateGMXExchangeRouter(address addr) external;
  function updateGMXRouter(address addr) external;
  function updateGMXDepositVault(address addr) external;
  function updateGMXWithdrawalVault(address addr) external;
  function updateGMXRoleStore(address addr) external;
  function updateMinAssetValue(uint256 value) external;
  function updateMaxAssetValue(uint256 value) external;

  function mintFee() external;
  function mint(address to, uint256 amt) external;
  function burn(address to, uint256 amt) external;
}

