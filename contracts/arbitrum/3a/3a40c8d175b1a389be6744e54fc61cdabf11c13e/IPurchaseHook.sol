// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.7;

//TODO natspec
interface IPurchaseHook {
  function hook(
    address purchaser,
    address recipient,
    uint256 amount,
    uint256 price
  ) external;
}

