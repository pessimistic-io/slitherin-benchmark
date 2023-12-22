// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "./IERC20.sol";

interface IERC677 is IERC20 {
  function transferAndCall(address to, uint value, bytes memory data) external returns (bool success);
}

