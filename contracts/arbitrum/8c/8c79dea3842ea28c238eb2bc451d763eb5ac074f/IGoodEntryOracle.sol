// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IAaveOracle} from "./IAaveOracle.sol";

/**
 * @title IGoodEntryOracle
 * @author GoodEntry
 * @notice Defines the basic interface for the Oracle, based on Aave Oracle
 */
interface IGoodEntryOracle is IAaveOracle{
  /**
   * @notice Returns the volatility of an asset address
   * @param asset The address of the asset
   * @param length The length in days used for the calculation, no more than 30 days
   * @return volatility The realized volatility of the asset as observed by the oracle X8 (100% = 1e8)
   * @dev Purely indicative and unreliable
   */
  function getAssetVolatility(address asset, uint8 length) external view returns (uint224 volatility);
  
  /// @notice Returns the risk free rate of money markets X8
  function getRiskFreeRate() external view returns (int256);
  /// @notice Sets the risk free rate of money markets
  function setRiskFreeRate(int256 riskFreeRate) external;
  /**
   * @dev Emitted after the risk-free rate is updated
   * @param riskFreeRate The risk free rate
   */
  event RiskFreeRateUpdated(int256 riskFreeRate);
  
  
  /// @notice Returns the risk free rate of money markets X8
  function getIVMultiplier() external view returns (uint16);
  /// @notice Sets the risk free rate of money markets
  function setIVMultiplier(uint16 ivMultiplier) external;
  /// @notice Emitted after the IV multiplier is updated
  event IVMultiplierUpdated(uint16 ivMultiplier);
  
  /**
   * @notice Updates a list of prices from a list of assets addresses
   * @param assets The list of assets addresses
   * @dev prices can be updated once daily for volatility calculation
   */
  function snapshotDailyAssetsPrices(address[] calldata assets) external;
  /**
   * @notice Gets the price of an asset at a given day
   * @param asset The asset address
   * @param thatDay The day, expressed in days since 1970, today is block.timestamp / 86400
   */
  function getAssetPriceAtDay(address asset, uint thatDay) external view returns (uint256);
  
  /**
   * @notice Gets the price of an option based on strike, tte and utilization rate
   */
  function getOptionPrice(bool isCall, address baseToken, address quoteToken, uint strike, uint timeToExpirySec, uint utilizationRateX8) 
    external view returns (uint optionPriceX8);
    
  /// @notice Get the price of an option based on BS parameters and utilization rate
  function getOptionPrice(bool isCall, address baseToken, address quoteToken, uint strike, uint timeToExpirySec, uint volatility, uint utilizationRate)
    external view returns (uint callPrice, uint putPrice);
    
  /// @notice Get the adjusted volatility for an asset over 10d, used in option pricing with IV premium over HV
  function getAdjustedVolatility(address baseToken, uint utilizationRate) external view returns (uint volatility);
}
