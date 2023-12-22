// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IAaveL2Encoder {
  function encodeSupplyParams(address asset, uint256 amount, uint16 referralCode) external view returns (bytes32);
  function encodeSupplyWithPermitParams(address asset, uint256 amount, uint16 referralCode, uint256 deadline, uint8 permitV, bytes32 permitR, bytes32 permitS) external view returns ( bytes32, bytes32, bytes32);
  function encodeBorrowParams(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode) external view returns (bytes32);
  function encodeRepayParams( address asset, uint256 amount, uint256 interestRateMode) external view returns (bytes32);
  function encodeWithdrawParams(address asset, uint256 amount) external view returns (bytes32);
}


