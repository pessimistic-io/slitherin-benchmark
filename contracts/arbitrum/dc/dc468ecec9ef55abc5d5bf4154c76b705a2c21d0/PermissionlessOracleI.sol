//SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4;

import "./HTokenI.sol";

import "./AggregatorV3Interface.sol";

/**
 * @title   PermissionlessOracleI interface for the Permissionless oracle
 * @author  Honey Labs Inc.
 * @custom:coauthor BowTiedPickle
 * @custom:coauthor m4rio
 */
interface PermissionlessOracleI {
  /**
   * @notice returns the price (in eth) for the floor of a collection
   * @param _collection address of the collection
   * @param _decimals adjust decimals of the returned price
   */
  function getFloorPrice(address _collection, uint256 _decimals) external view returns (uint128, uint128);

  /**
   * @notice returns the latest price for a given pair
   * @param _erc20 the erc20 we want to get the price for in USD
   * @param _decimals decimals to denote the result in
   */
  function getUnderlyingPriceInUSD(IERC20 _erc20, uint256 _decimals) external view returns (uint256);

  /**
   * @notice get price of eth
   * @param _decimals adjust decimals of the returned price
   */
  function getEthPrice(uint256 _decimals) external view returns (uint256);

  /**
   * @notice get price feeds for a token
   * @return returns the Chainlink Aggregator interface
   */
  function priceFeeds(IERC20 _token) external view returns (AggregatorV3Interface);

  /**
   * @notice returns the update threshold for a specific _collection
   */
  function updateThreshold(address _collection) external view returns (uint256);

  /**
   * @notice returns the number of floors for a specific _collection
   * @param _address address of the collection
   *
   */
  function getNoOfFloors(address _address) external view returns (uint256);

  /**
   * @notice returns the last updated timestamp for a specific _collection
   * @param _collection address of the collection
   *
   */
  function getLastUpdated(address _collection) external view returns (uint256);
}

