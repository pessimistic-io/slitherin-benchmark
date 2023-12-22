// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.8.0;

/**
 * @title IPriceOracle interface
 * @notice Defines the basic interface for a Price oracle.
 **/
interface IPriceOracle {
  /**
   * @notice Returns the asset price
   * @return The asset price
   **/
  function getAssetPrice() external view returns (uint256);

  /**
   * @notice Set the price of the asset price
   * @param price The asset price
   **/
  function setAssetPrice(uint256 price) external;
}
