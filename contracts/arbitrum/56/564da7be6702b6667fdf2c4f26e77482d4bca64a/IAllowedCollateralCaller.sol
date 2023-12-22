// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {ICollateral} from "./ICollateral.sol";

interface IAllowedCollateralCaller {
  event CollateralChange(address collateral);

  error MsgSenderNotCollateral();

  function setCollateral(ICollateral newCollateral) external;

  function getCollateral() external view returns (ICollateral);
}

