// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IStrategyDystopia {
  function MAX_CALL_FEE() external view returns (uint256);

  function MAX_FEE() external view returns (uint256);

  function WITHDRAWAL_FEE_CAP() external view returns (uint256);

  function WITHDRAWAL_MAX() external view returns (uint256);

  function balanceOf() external view returns (uint256);

  function balanceOfPool() external view returns (uint256);

  function balanceOfWant() external view returns (uint256);

  function beforeDeposit() external;

  function callFee() external view returns (uint256);

  function chef() external view returns (address);

  function deposit() external;

  function dystRouter() external view returns (address);

  function fee1() external view returns (uint256);

  function fee2() external view returns (uint256);

  function feeOnProfits() external view returns (uint256);

  function feeRecipient1() external view returns (address);

  function feeRecipient2() external view returns (address);

  function harvest(address callFeeRecipient) external;

  function harvest() external;

  function harvestOnDeposit() external view returns (bool);

  function isStableLp0Lp1() external view returns (bool);

  function isStableOutputLp0() external view returns (bool);

  function isStableOutputLp1() external view returns (bool);

  function isStableOutputNative() external view returns (bool);

  function keeper() external view returns (address);

  function lastHarvest() external view returns (uint256);

  function lpToken0() external view returns (address);

  function lpToken1() external view returns (address);

  function managerHarvest() external;

  function native() external view returns (address);

  function nativeTokenBalance() external view returns (uint256);

  function output() external view returns (address);

  function outputBalance() external view returns (uint256);

  function outputToLp0Route() external view returns (address from, address to, bool stable);

  function outputToLp1Route() external view returns (address from, address to, bool stable);

  function outputToNativeRoute() external view returns (address from, address to, bool stable);

  function owner() external view returns (address);

  function panic() external;

  function pause() external;

  function paused() external view returns (bool);

  function pendingRewardsFunctionName() external view returns (string memory);

  function retireStrat() external;

  function strategist() external view returns (address);

  function strategistFee() external view returns (uint256);

  function unpause() external;

  function vault() external view returns (address);

  function want() external view returns (address);

  function withdraw(uint256 _amount) external;

  function withdrawalFee() external view returns (uint256);
}

