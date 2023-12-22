// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {SafeCast} from "./SafeCast.sol";
import {IPolicyPool} from "./IPolicyPool.sol";
import {IPremiumsAccount} from "./IPremiumsAccount.sol";
import {RiskModule} from "./RiskModule.sol";
import {Policy} from "./Policy.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {IPriceOracle} from "./IPriceOracle.sol";

/**
 * @title ChainlinkPriceOracle
 * @dev Implementation of IPriceOracle using two underlying chainlink oracles. One with the price of the asset and
 *      other (referenceOracle - optional) with the price of the asset you want to denominate the asset price.
 * @custom:security-contact security@ensuro.co
 * @author Ensuro
 */
contract ChainlinkPriceOracle is IPriceOracle {
  using WadRayMath for uint256;

  uint8 internal constant WAD_DECIMALS = 18;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  AggregatorV3Interface internal immutable _assetOracle;
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  AggregatorV3Interface internal immutable _referenceOracle;
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  uint256 internal immutable _oracleTolerance;

  /**
   * @dev Constructs the PriceRiskModule.
   *      Note that, although it's supported that assetOracle_ and  referenceOracle_ have different number
   *      of decimals, they're assumed to be in the same denomination. For instance, assetOracle_ could be
   *      WMATIC/ETH and referenceOracle_ could be for USDC/ETH.
   *      This cannot be validated by the contract, so be careful when constructing.
   *
   * @param assetOracle_ Address of the price feed oracle for the asset
   * @param referenceOracle_ Address of the price feed oracle for the reference currency. If it's
   *                         the zero address the asset price will be considered directly.
   * @param oracleTolerance_ Max acceptable age of price data, in seconds
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    AggregatorV3Interface assetOracle_,
    AggregatorV3Interface referenceOracle_,
    uint256 oracleTolerance_
  ) {
    require(
      address(assetOracle_) != address(0),
      "PriceRiskModule: assetOracle_ cannot be the zero address"
    );
    _assetOracle = assetOracle_;
    _referenceOracle = referenceOracle_;
    _oracleTolerance = oracleTolerance_;
  }

  /**
   * @dev Returns the price of the asset
   *
   * Requirements:
   * - The oracle(s) are functional, returning non zero values and updated after (block.timestamp - oracleTolerance())
   *
   * @return If referenceOracle() != address(0), returns the price of the asset expressed in terms of the reference
   *         asset, in Wad (18 decimals)
   *         If referenceOracle() == address(0), returns the price of the asset expressed in the denomination of
   *         assetOracle(), in Wad (18 decimals)
   */
  function getCurrentPrice() public view virtual override returns (uint256) {
    if (address(_referenceOracle) == address(0)) {
      return _scalePrice(_getLatestPrice(_assetOracle), _assetOracle.decimals(), WAD_DECIMALS);
    } else {
      return _getExchangeRate(_assetOracle, _referenceOracle);
    }
  }

  /**
   * @dev Calculates the exchange rate between the prices returned by the two aggregators
   *      Assumes that both aggregators are returning prices using the same quote.
   *      Although it's usual that the aggregators return prices with the same number of
   *      decimals, this is not required. Both prices will be scaled to Wad before calculating the
   *      rate.
   * @param base the aggregator for the base
   * @param quote the aggregator for the quote asset.
   * @return The exchange rate from/to in Wad
   */
  function _getExchangeRate(AggregatorV3Interface base, AggregatorV3Interface quote)
    internal
    view
    returns (uint256)
  {
    uint256 basePrice = _scalePrice(_getLatestPrice(base), base.decimals(), WAD_DECIMALS);
    require(basePrice != 0, "Price from not available");

    uint256 quotePrice = _scalePrice(_getLatestPrice(quote), quote.decimals(), WAD_DECIMALS);
    require(quotePrice != 0, "Price to not available");

    return basePrice.wadDiv(quotePrice);
  }

  function _getLatestPrice(AggregatorV3Interface oracle) internal view returns (uint256) {
    (, int256 price, , uint256 updatedAt, ) = oracle.latestRoundData();
    require(updatedAt > block.timestamp - _oracleTolerance, "Price is older than tolerable");

    return SafeCast.toUint256(price);
  }

  function _scalePrice(
    uint256 price,
    uint8 priceDecimals,
    uint8 decimals
  ) internal pure returns (uint256) {
    if (priceDecimals < decimals) return price * 10**(decimals - priceDecimals);
    else return price / 10**(priceDecimals - decimals);
  }

  function referenceOracle() external view returns (AggregatorV3Interface) {
    return _referenceOracle;
  }

  function assetOracle() external view returns (AggregatorV3Interface) {
    return _assetOracle;
  }

  function oracleTolerance() external view returns (uint256) {
    return _oracleTolerance;
  }
}

