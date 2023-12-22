// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ISwap {
  function swapTokens(
    uint256 _amountToSwap,
    address _fromAsset,
    address _toAsset,
    address _receiver
  ) external returns (uint256 amountReturned_, uint256 feesPaidInOut_);
}
