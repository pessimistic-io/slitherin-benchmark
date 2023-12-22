// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable not-rely-on-time */

import "./ISwapRouter.sol";
import "./IERC20.sol";

import "./IOracle.sol";

/// @title Helper functions for dealing with various forms of price feed oracles.
/// @notice Maintains a price cache and updates the current price if needed.
/// In the best case scenario we have a direct oracle from the token to the native asset.
/// Also support tokens that have no direct price oracle to the native asset.
/// Sometimes oracles provide the price in the opposite direction of what we need in the moment.
abstract contract OracleHelper {
  struct TokenPrice {
    /// @notice The cached token price from the Oracle, always in (ether-per-token) * PRICE_DENOMINATOR format
    uint256 cachedPrice;
    /// @notice The timestamp of a block when the cached price was updated
    uint256 cachedPriceTimestamp;
  }

  uint256 private constant PRICE_DENOMINATOR = 1e26;

  /// @notice The price cache will be returned without even fetching the oracles for this number of seconds
  uint256 private constant cacheTimeToLive = 1 days;

  /// @notice The Oracle contract used to fetch the latest ETH prices
  IOracle private nativeOracle;

  mapping(IERC20 => TokenPrice) public prices;

  event TokenPriceUpdated(uint256 currentPrice, uint256 previousPrice, uint256 cachedPriceTimestamp);

  constructor(IOracle _nativeOracle) {
    nativeOracle = _nativeOracle;
  }

  /// @notice Updates the token price by fetching the latest price from the Oracle.
  function _updateCachedPrice(
    IERC20 token,
    IOracle tokenOracle,
    bool toNative,
    bool force
  ) public returns (uint256 newPrice) {
    TokenPrice memory tokenPrice = prices[token];

    uint256 oldPrice = tokenPrice.cachedPrice;
    uint256 cacheAge = block.timestamp - tokenPrice.cachedPriceTimestamp;

    if (!force && cacheAge <= cacheTimeToLive) {
      return oldPrice;
    }

    uint256 price = calculatePrice(tokenOracle, toNative);

    newPrice = price;
    tokenPrice.cachedPrice = newPrice;
    tokenPrice.cachedPriceTimestamp = block.timestamp;

    prices[token] = tokenPrice;

    emit TokenPriceUpdated(newPrice, oldPrice, tokenPrice.cachedPriceTimestamp);
  }

  function _removeTokenPrice(IERC20 token) internal {
    delete prices[token];
  }

  function calculatePrice(IOracle tokenOracle, bool toNative) public view returns (uint256 price) {
    // dollar per token (or native per token)
    uint256 tokenPrice = fetchPrice(tokenOracle);
    uint256 tokenOracleDecimalPower = 10 ** tokenOracle.decimals();

    if (toNative) {
      return (PRICE_DENOMINATOR * tokenPrice) / tokenOracleDecimalPower;
    }

    // dollar per native
    uint256 nativePrice = fetchPrice(nativeOracle);
    uint256 nativeOracleDecimalPower = 10 ** nativeOracle.decimals();

    // nativePrice is normalized as native per dollar
    nativePrice = (PRICE_DENOMINATOR * nativeOracleDecimalPower) / nativePrice;

    // multiplying by nativeAssetPrice that is  ethers-per-dollar
    // => result = (native / dollar) * (dollar / token) = native / token
    price = (nativePrice * tokenPrice) / tokenOracleDecimalPower;
  }

  /// @notice Fetches the latest price from the given Oracle.
  /// @dev This function is used to get the latest price from the tokenOracle or nativeOracle.
  /// @param _oracle The Oracle contract to fetch the price from.
  /// @return price The latest price fetched from the Oracle.
  function fetchPrice(IOracle _oracle) internal view returns (uint256 price) {
    (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) = _oracle.latestRoundData();
    require(answer > 0, "TPM: Chainlink price <= 0");
    // 2 days old price is considered stale since the price is updated every 24 hours
    require(updatedAt >= block.timestamp - 60 * 60 * 24 * 2, "TPM: Incomplete round");
    require(answeredInRound >= roundId, "TPM: Stale price");
    price = uint256(answer);
  }

  function getCachedPrice(IERC20 token) internal view returns (uint256 price) {
    return prices[token].cachedPrice;
  }

  function getCachedPriceTimestamp(IERC20 token) internal view returns (uint256) {
    return prices[token].cachedPriceTimestamp;
  }
}

