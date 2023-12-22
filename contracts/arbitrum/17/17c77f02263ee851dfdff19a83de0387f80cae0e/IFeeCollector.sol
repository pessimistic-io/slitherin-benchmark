// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IFeeCollector {
  function receiveNative() external payable;

  function receiveToken(address tokenAddress, uint256 amount) external;
}

