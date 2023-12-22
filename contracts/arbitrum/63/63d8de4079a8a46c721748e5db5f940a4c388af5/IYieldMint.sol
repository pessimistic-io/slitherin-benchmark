// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

interface IYieldMint {
  function depositWeth(address userAddress) external payable returns (uint256);
}

