// SPDX-License-Identifier: BUSL-1.1

// (c) Gearbox Holdings, 2022

// This code was largely inspired by Gearbox Protocol

pragma solidity 0.8.16;

import {IVersion} from "./IVersion.sol";

interface IPriceOracleEvents {
  /// @dev Emits when a quote price feed is changed
  event ChangedQuotePriceFeed(address indexed quotePriceFeed, uint8 decimals);

  /// @dev Emits when a new price feed is added
  event NewPriceFeed(address indexed token, address indexed priceFeed);
}

interface IPriceOracleExceptions {
  /// @dev Thrown if a price feed returns 0
  error ZeroPriceException();

  /// @dev Thrown if the last recorded result was not updated in the last round
  error ChainPriceStaleException();

  /// @dev Thrown on attempting to get a result for a token that does not have a price feed
  error PriceOracleNotExistsException();

  /// @dev Thrown on attempting to set a token price feed to an address that is not a
  ///      correct price feed
  error IncorrectPriceFeedException();
}

interface IPriceOracle is IPriceOracleEvents, IPriceOracleExceptions, IVersion {
  /// @dev Sets a quote price feed if it doesn't exist, or updates an existing one
  /// @param quotePriceFeed Address of a Fiat price feed adhering to Chainlink's interface
  function addQuotePriceFeed(address quotePriceFeed) external;

  /// @dev Sets a price feed if it doesn't exist, or updates an existing one
  /// @param token Address of the token to set the price feed for
  /// @param priceFeed Address of a USD price feed adhering to Chainlink's interface
  function addPriceFeed(address token, address priceFeed) external;

  /// @dev Returns token's price in USD (8 decimals)
  /// @param token The token to compute the price for
  function getPrice(address token) external view returns (uint256);

  /// @dev Converts a quantity of an asset to USD (decimals = 8).
  /// @param amount Amount to convert
  /// @param token Address of the token to be converted
  function convertToUSD(
    uint256 amount,
    address token
  ) external view returns (uint256);

  /// @dev Converts a quantity of USD (decimals = 8) to an equivalent amount of an asset
  /// @param amount Amount to convert
  /// @param token Address of the token converted to
  function convertFromUSD(
    uint256 amount,
    address token
  ) external view returns (uint256);

  /// @dev Converts one asset into another
  /// @param amount Amount to convert
  /// @param tokenFrom Address of the token to convert from
  /// @param tokenTo Address of the token to convert to
  function convert(
    uint256 amount,
    address tokenFrom,
    address tokenTo
  ) external view returns (uint256);

  /// @dev Returns token's price in Derived Fiat (8 decimals)
  /// @param token The token to compute the price for
  function getPriceInDerivedFiat(address token) external view returns (uint256);

  /// @dev Converts a quantity of an asset to Derived Fiat (decimals = 8).
  /// @param amount Amount to convert
  /// @param token Address of the token to be converted
  function convertToDerivedFiat(
    uint256 amount,
    address token
  ) external view returns (uint256);

  /// @dev Converts a quantity of Derived Fiat (decimals = 8) to an equivalent amount of an asset
  /// @param amount Amount to convert
  /// @param token Address of the token converted to
  function convertFromDerivedFiat(
    uint256 amount,
    address token
  ) external view returns (uint256);

  /// @dev Converts one asset into another with Derived Fiat
  /// @param amount Amount to convert
  /// @param tokenFrom Address of the token to convert from
  /// @param tokenTo Address of the token to convert to
  function convertInDerivedFiat(
    uint256 amount,
    address tokenFrom,
    address tokenTo
  ) external view returns (uint256);

  /// @dev Returns the price feed address for the passed token
  /// @param token Token to get the price feed for
  function priceFeeds(address token) external view returns (address priceFeed);

  /// @dev Returns the price feed for the passed token,
  ///      with additional parameters
  /// @param token Token to get the price feed for
  function priceFeedsWithFlags(
    address token
  ) external view returns (address priceFeed, bool skipCheck, uint256 decimals);
}

