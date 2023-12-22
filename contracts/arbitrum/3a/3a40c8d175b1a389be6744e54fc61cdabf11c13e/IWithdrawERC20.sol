// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.7;

// TODO: add natspec comments
interface IWithdrawERC20 {
  function withdrawERC20(address[] calldata erc20Tokens, uint256[] calldata amounts) external;
}

