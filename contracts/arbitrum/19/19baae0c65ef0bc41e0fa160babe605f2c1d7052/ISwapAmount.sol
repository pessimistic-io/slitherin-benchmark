// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.17;

interface ISwapAmount {
  function getAmount (bytes memory params) external view returns (uint amount);
}

