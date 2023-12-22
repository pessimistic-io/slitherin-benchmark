// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IDexter } from "./IDexter.sol";

interface ISwitchCollateralRouter {
  function execute(uint256 _amount, address[] calldata _path) external returns (uint256);
}

