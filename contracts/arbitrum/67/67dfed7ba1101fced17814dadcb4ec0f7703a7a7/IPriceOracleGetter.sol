// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.8.0;

/**
 * @title IPriceOracleGetter interface
 * @notice Interface for the price oracle.
 **/

interface IPriceOracleGetter {
  /**
   * @dev returns the asset price
   * @param asset the address of the asset
   * @return the price of the asset
   **/
  function getAssetPrice(address asset) external view returns (uint256);
}

