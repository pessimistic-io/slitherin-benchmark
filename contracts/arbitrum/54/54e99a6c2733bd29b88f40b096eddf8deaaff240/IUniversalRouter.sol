// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

interface IUniversalRouter {
  function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable ;
}

