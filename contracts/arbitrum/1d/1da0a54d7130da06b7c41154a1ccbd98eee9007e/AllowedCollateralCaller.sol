// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./IAllowedCollateralCaller.sol";
import "./ICollateral.sol";

contract AllowedCollateralCaller is IAllowedCollateralCaller {
  ICollateral internal _collateral;

  modifier onlyCollateral() {
    require(msg.sender == address(_collateral), "msg.sender != collateral");
    _;
  }

  function setCollateral(ICollateral collateral) public virtual override {
    _collateral = collateral;
    emit CollateralChange(address(collateral));
  }

  function getCollateral() external view override returns (ICollateral) {
    return _collateral;
  }
}

