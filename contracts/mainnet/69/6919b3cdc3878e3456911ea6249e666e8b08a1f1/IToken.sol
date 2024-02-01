// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import { IERC20 } from "./IERC20.sol";

interface IWETHToken is IERC20 {
  function withdraw(uint256 amount) external;
}

