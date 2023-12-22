// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPriceOracle, IPriceOracleGetter} from "./IPriceOracle.sol";
import "./SyntheX.sol";
import "./AggregatorInterface.sol";
import "./Ownable.sol";

/**
 * @title PriceOracle
 * @author Aave
 * @notice Contract to get asset prices, manage price sources and update the fallback oracle
 * - Use of Chainlink Aggregators as first source of price
 * - If the returned price by a Chainlink aggregator is <= 0, the call is forwarded to a fallback oracle
 * - Owned by the Aave governance
 */
contract PriceOracle is IPriceOracle {
  SyntheX public immutable synthex;

  // Map of asset price sources (asset => priceSource)
  mapping(address => AggregatorInterface) private assetsSources;

  IPriceOracleGetter private _fallbackOracle;
  address public immutable override BASE_CURRENCY;
  uint public immutable override BASE_CURRENCY_UNIT;
  /**
   * @dev Only asset listing or pool admin can call functions marked by this modifier.
   */
  modifier onlyAssetListingOrPoolAdmins() {
    require(
            synthex.isL1Admin(msg.sender),
            Errors.CALLER_NOT_L1_ADMIN
        );
    _;
  }

  /**
   * @notice Constructor
   * @param _synthex The address of the new System
   * @param assets The addresses of the assets
   * @param sources The address of the source of each asset
   * @param fallbackOracle The address of the fallback oracle to use if the data of an
   *        aggregator is not consistent
   * @param baseCurrency The base currency used for the price quotes. If USD is used, base currency is 0x0
   * @param baseCurrencyUnit The unit of the base currency
   */
  constructor(
    SyntheX _synthex,
    address[] memory assets,
    address[] memory sources,
    address fallbackOracle,
    address baseCurrency,
    uint baseCurrencyUnit
  ) {
    synthex = _synthex;
    _setFallbackOracle(fallbackOracle);
    _setAssetsSources(assets, sources);
    BASE_CURRENCY = baseCurrency;
    BASE_CURRENCY_UNIT = baseCurrencyUnit;
    emit BaseCurrencySet(baseCurrency, baseCurrencyUnit);
  }

  /// @inheritdoc IPriceOracle
  function setAssetSources(address[] calldata assets, address[] calldata sources)
    external
    override
    onlyAssetListingOrPoolAdmins
  {
    _setAssetsSources(assets, sources);
  }

  /// @inheritdoc IPriceOracle
  function setFallbackOracle(address fallbackOracle)
    external
    override
    onlyAssetListingOrPoolAdmins
  {
    _setFallbackOracle(fallbackOracle);
  }

  /**
   * @notice Internal function to set the sources for each asset
   * @param assets The addresses of the assets
   * @param sources The address of the source of each asset
   */
  function _setAssetsSources(address[] memory assets, address[] memory sources) internal {
    require(assets.length == sources.length, Errors.INVALID_ARGUMENT);
    for (uint256 i = 0; i < assets.length; i++) {
      assetsSources[assets[i]] = AggregatorInterface(sources[i]);
      emit AssetSourceUpdated(assets[i], sources[i]);
    }
  }

  /**
   * @notice Internal function to set the fallback oracle
   * @param fallbackOracle The address of the fallback oracle
   */
  function _setFallbackOracle(address fallbackOracle) internal {
    _fallbackOracle = IPriceOracleGetter(fallbackOracle);
    emit FallbackOracleUpdated(fallbackOracle);
  }

  /// @inheritdoc IPriceOracleGetter
  function getAssetPrice(address asset) public view override returns (uint) {
    AggregatorInterface source = assetsSources[asset];

    if (asset == BASE_CURRENCY) {
      return BASE_CURRENCY_UNIT;
    } else if (address(source) == address(0)) {
      return _fallbackOracle.getAssetPrice(asset);
    } else {
      int256 price = source.latestAnswer();
      if (price > 0) {
        return uint256(price);
      } else {
        return _fallbackOracle.getAssetPrice(asset);
      }
    }
  }

  /// @inheritdoc IPriceOracle
  function getAssetsPrices(address[] calldata assets)
    external
    view
    override
    returns (uint[] memory)
  {
    uint[] memory prices = new uint[](assets.length);
    for (uint256 i = 0; i < assets.length; i++) {
      prices[i] = getAssetPrice(assets[i]);
    }
    return prices;
  }

  /// @inheritdoc IPriceOracle
  function getSourceOfAsset(address asset) external view override returns (address) {
    return address(assetsSources[asset]);
  }

  /// @inheritdoc IPriceOracle
  function getFallbackOracle() external view returns (address) {
    return address(_fallbackOracle);
  }
}
