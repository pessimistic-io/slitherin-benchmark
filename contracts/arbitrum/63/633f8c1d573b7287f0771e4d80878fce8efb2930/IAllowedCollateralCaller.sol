// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./ICollateral.sol";

interface IAllowedCollateralCaller {
  event CollateralChange(address collateral);

  function setCollateral(ICollateral newCollateral) external;

  function getCollateral() external view returns (ICollateral);
}

