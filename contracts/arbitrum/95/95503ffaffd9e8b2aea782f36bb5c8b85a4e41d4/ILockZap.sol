// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ILockZap {
  function zap(
    bool _borrow,
    uint256 _wethAmt,
    uint256 _rdntAmt,
    uint256 _lockTypeIndex
  ) external payable returns (uint256);
}

