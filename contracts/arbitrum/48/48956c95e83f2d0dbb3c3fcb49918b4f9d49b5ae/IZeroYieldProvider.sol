// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./AaveILendingPool.sol";

interface IZeroYieldProvider is ILendingPool {
  /**
   * @dev Emitted when asset authorization status changes
   * @param asset The address of the underlying asset
   * @param isAuthorized New authorization status of the asset
   **/
  event SetAssetAuthorization(address asset, bool isAuthorized);

  /**
   * @dev Returns the authorization status of the asset
   * @param asset The address of the underlying asset
   **/
  function isAssetAuthorized(address asset) external returns (bool);

  /**
   * @dev Sets authorization status of an asset on the no yield provider
   * @param asset The address of the underlying asset
   * @param isAuthorized The authorization status of the asset to be set
   **/
  function setAssetAuthorization(address asset, bool isAuthorized) external;
}

