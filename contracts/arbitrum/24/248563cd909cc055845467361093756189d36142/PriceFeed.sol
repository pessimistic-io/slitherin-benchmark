// SPDX-License-Identifier: BUSL-1.1

// (c) Gearbox Holdings, 2022

// This code was largely inspired by Gearbox Protocol

pragma solidity 0.8.16;

import {Address} from "./Address.sol";
import {Ownable} from "./Ownable.sol";
import {ERC20} from "./ERC20.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

import {PriceFeedChecker} from "./PriceFeedChecker.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {IPriceFeedType} from "./IPriceFeedType.sol";
import {IConfiguration} from "./IConfiguration.sol";

// EXCEPTIONS
import {ZeroAddressException, AddressIsNotContractException, IncorrectTokenContractException} from "./IErrors.sol";

// STRUCTS

struct PriceFeedConfig {
  address token;
  address priceFeed;
}

// CONSTANTS

uint256 constant SKIP_PRICE_CHECK_FLAG = 1 << 161;
uint256 constant DECIMALS_SHIFT = 162;

/// @title Price Oracle
/// @author Gearbox
/// @notice Works as router and provide cross rates converting via USD
/// @dev All function calls are currently implemented
/// @custom:security-contact security@munchies.money
contract PriceFeed is Ownable, PriceFeedChecker, IPriceOracle {
  using Address for address;

  /// @dev Map of token addresses to corresponding price feeds and their parameters,
  ///      encoded into a single uint256
  mapping(address => uint256) internal _priceFeeds;

  // Contract version
  uint256 public constant version = 1;

  address public immutable link;

  IConfiguration public immutable configuration;

  /// @dev Chainlink quote asset price feed
  AggregatorV3Interface public quotePriceFeed;

  /// @dev Chainlink quote asset price feed decimals
  uint8 public quotePriceFeedDecimals;

  constructor(
    address quotePriceFeed_,
    PriceFeedConfig[] memory defaults_,
    address link_,
    address configuration_
  ) {
    // LINK token
    link = link_;

    // Protocol configurations
    configuration = IConfiguration(configuration_);

    _addQuotePriceFeed(quotePriceFeed_);

    uint256 len = defaults_.length;

    for (uint256 i = 0; i < len; ) {
      _addPriceFeed(defaults_[i].token, defaults_[i].priceFeed); // F:[PO-1]

      unchecked {
        ++i;
      }
    }
  }

  /// @inheritdoc IPriceOracle
  function addQuotePriceFeed(address quotePriceFeed_) external onlyOwner {
    _addQuotePriceFeed(quotePriceFeed_);
  }

  /// @dev IMPLEMENTATION: addQuotePriceFeed
  /// @param quotePriceFeed_ Address of a Fiat price feed adhering to Chainlink's interface
  function _addQuotePriceFeed(address quotePriceFeed_) internal {
    if (quotePriceFeed_ == address(0)) revert ZeroAddressException(); // F:[PO-2]

    if (!quotePriceFeed_.isContract())
      revert AddressIsNotContractException(quotePriceFeed_); // F:[PO-2]

    uint8 decimals = AggregatorV3Interface(quotePriceFeed_).decimals();

    if (decimals != 8) revert IncorrectPriceFeedException(); // F:[PO-2]

    try AggregatorV3Interface(quotePriceFeed_).latestRoundData() returns (
      uint80 roundID,
      int256 price,
      uint256,
      uint256 updatedAt,
      uint80 answeredInRound
    ) {
      // Checks result
      _checkAnswer(roundID, price, updatedAt, answeredInRound);
    } catch {
      revert IncorrectPriceFeedException(); // F:[PO-2]
    }

    quotePriceFeed = AggregatorV3Interface(quotePriceFeed_);
    quotePriceFeedDecimals = decimals;

    emit ChangedQuotePriceFeed(quotePriceFeed_, decimals); // F:[PO-3]
  }

  /// @inheritdoc IPriceOracle
  function addPriceFeed(address token, address priceFeed) external onlyOwner {
    _addPriceFeed(token, priceFeed);
  }

  /// @dev IMPLEMENTATION: addPriceFeed
  /// @param token Address of the token to set the price feed for
  /// @param priceFeed Address of a USD price feed adhering to Chainlink's interface
  function _addPriceFeed(address token, address priceFeed) internal {
    if (token == address(0) || priceFeed == address(0))
      revert ZeroAddressException(); // F:[PO-2]

    if (!token.isContract()) revert AddressIsNotContractException(token); // F:[PO-2]

    if (!priceFeed.isContract())
      revert AddressIsNotContractException(priceFeed); // F:[PO-2]

    try AggregatorV3Interface(priceFeed).decimals() returns (uint8 _decimals) {
      if (_decimals != 8) revert IncorrectPriceFeedException(); // F:[PO-2]
    } catch {
      revert IncorrectPriceFeedException(); // F:[PO-2]
    }

    bool skipCheck;

    try IPriceFeedType(priceFeed).skipPriceCheck() returns (bool property) {
      skipCheck = property; // F:[PO-2]
    } catch {}

    uint8 decimals;

    try ERC20(token).decimals() returns (uint8 _decimals) {
      if (_decimals > 18) revert IncorrectTokenContractException(); // F:[PO-2]

      decimals = _decimals; // F:[PO-3]
    } catch {
      revert IncorrectTokenContractException(); // F:[PO-2]
    }

    try AggregatorV3Interface(priceFeed).latestRoundData() returns (
      uint80 roundID,
      int256 price,
      uint256,
      uint256 updatedAt,
      uint80 answeredInRound
    ) {
      // Checks result if skipCheck is not set
      if (!skipCheck) _checkAnswer(roundID, price, updatedAt, answeredInRound);
    } catch {
      revert IncorrectPriceFeedException(); // F:[PO-2]
    }

    _setPriceFeedWithFlags(token, priceFeed, skipCheck, decimals);

    emit NewPriceFeed(token, priceFeed); // F:[PO-3]
  }

  /// @inheritdoc IPriceOracle
  function getPrice(
    address token
  ) public view override returns (uint256 price) {
    (price, ) = _getPrice(token);
  }

  /// @dev IMPLEMENTATION: getPrice
  function _getPrice(
    address token
  ) internal view returns (uint256 price, uint256 decimals) {
    address priceFeed;

    bool skipCheck;

    (priceFeed, skipCheck, decimals) = priceFeedsWithFlags(token); //

    (
      uint80 roundID,
      int256 _price,
      ,
      uint256 updatedAt,
      uint80 answeredInRound
    ) = AggregatorV3Interface(priceFeed).latestRoundData(); // F:[PO-6]

    // Checks if SKIP_PRICE_CHECK_FLAG is not set
    if (!skipCheck) _checkAnswer(roundID, _price, updatedAt, answeredInRound); // F:[PO-5]

    price = (uint256(_price)); // F:[PO-6]
  }

  /// @inheritdoc IPriceOracle
  function convertToUSD(
    uint256 amount,
    address token
  ) public view override returns (uint256) {
    (uint256 price, uint256 decimals) = _getPrice(token);

    return (amount * price) / (10 ** decimals); // F:[PO-7]
  }

  /// @inheritdoc IPriceOracle
  function convertFromUSD(
    uint256 amount,
    address token
  ) public view override returns (uint256) {
    (uint256 price, uint256 decimals) = _getPrice(token);

    return (amount * (10 ** decimals)) / price; // F:[PO-7]
  }

  /// @inheritdoc IPriceOracle
  function convert(
    uint256 amount,
    address tokenFrom,
    address tokenTo
  ) public view override returns (uint256) {
    return convertFromUSD(convertToUSD(amount, tokenFrom), tokenTo); // F:[PO-8]
  }

  /// @inheritdoc IPriceOracle
  function getPriceInDerivedFiat(
    address token
  ) public view override returns (uint256 price) {
    (price, ) = _getPriceInDerivedFiat(token);
  }

  /// @dev IMPLEMENTATION: getPriceInDerivedFiat
  /// @dev Further audit this function later
  function _getPriceInDerivedFiat(
    address token
  ) internal view returns (uint256 price, uint256 decimals) {
    uint8 _decimals = 8;

    int256 decimals_ = int256(10 ** uint256(_decimals));

    address priceFeed;

    bool skipCheck;

    (priceFeed, skipCheck, decimals) = priceFeedsWithFlags(token); //

    (
      uint80 baseRoundID,
      int256 basePrice,
      ,
      uint256 baseUpdatedAt,
      uint80 baseAnsweredInRound
    ) = AggregatorV3Interface(priceFeed).latestRoundData(); // F:[PO-6]

    // Checks if SKIP_PRICE_CHECK_FLAG is not set
    if (!skipCheck)
      _checkAnswer(baseRoundID, basePrice, baseUpdatedAt, baseAnsweredInRound); // F:[PO-5]

    uint8 baseDecimals = AggregatorV3Interface(priceFeed).decimals();

    basePrice = _scalePrice(basePrice, baseDecimals, _decimals); // F:[PO-6]

    (
      uint80 quoteRoundID,
      int256 quotePrice,
      ,
      uint256 quoteUpdatedAt,
      uint80 quoteAnsweredInRound
    ) = AggregatorV3Interface(address(quotePriceFeed)).latestRoundData(); // F:[PO-6]

    // Checks
    _checkAnswer(
      quoteRoundID,
      quotePrice,
      quoteUpdatedAt,
      quoteAnsweredInRound
    ); // F:[PO-5]

    uint8 quoteDecimals = quotePriceFeedDecimals;

    quotePrice = _scalePrice(quotePrice, quoteDecimals, _decimals);

    price = uint256((basePrice * decimals_) / quotePrice);
  }

  /// @dev Further audit this function later
  function _scalePrice(
    int256 _price,
    uint8 _priceDecimals,
    uint8 _decimals
  ) internal pure returns (int256) {
    if (_priceDecimals < _decimals) {
      return _price * int256(10 ** uint256(_decimals - _priceDecimals));
    } else if (_priceDecimals > _decimals) {
      return _price / int256(10 ** uint256(_priceDecimals - _decimals));
    }
    return _price;
  }

  /// @inheritdoc IPriceOracle
  function convertToDerivedFiat(
    uint256 amount,
    address token
  ) public view override returns (uint256) {
    (uint256 price, uint256 decimals) = _getPriceInDerivedFiat(token);

    return (amount * price) / (10 ** decimals); // F:[PO-7]
  }

  /// @inheritdoc IPriceOracle
  function convertFromDerivedFiat(
    uint256 amount,
    address token
  ) public view override returns (uint256) {
    (uint256 price, uint256 decimals) = _getPriceInDerivedFiat(token);

    return (amount * (10 ** decimals)) / price; // F:[PO-7]
  }

  /// @inheritdoc IPriceOracle
  function convertInDerivedFiat(
    uint256 amount,
    address tokenFrom,
    address tokenTo
  ) public view override returns (uint256) {
    return
      convertFromDerivedFiat(convertToDerivedFiat(amount, tokenFrom), tokenTo); // F:[PO-8]
  }

  /// @inheritdoc IPriceOracle
  function priceFeeds(
    address token
  ) external view override returns (address priceFeed) {
    (priceFeed, , ) = priceFeedsWithFlags(token); // F:[PO-3]
  }

  /// @inheritdoc IPriceOracle
  function priceFeedsWithFlags(
    address token
  )
    public
    view
    override
    returns (address priceFeed, bool skipCheck, uint256 decimals)
  {
    uint256 pf = _priceFeeds[token]; // F:[PO-3]

    if (pf == 0) revert PriceOracleNotExistsException();

    priceFeed = address(uint160(pf)); // F:[PO-3]

    skipCheck = pf & SKIP_PRICE_CHECK_FLAG != 0; // F:[PO-3]

    decimals = pf >> DECIMALS_SHIFT;
  }

  /// @dev Encodes the price feed address with parameters into a uint256,
  ///      and saves it into a map
  /// @param token Address of the token to add the price feed for
  /// @param priceFeed Address of the price feed
  /// @param skipCheck Whether price feed result sanity checks should be skipped
  /// @param decimals Decimals for the price feed's result
  function _setPriceFeedWithFlags(
    address token,
    address priceFeed,
    bool skipCheck,
    uint8 decimals
  ) internal {
    uint256 value = uint160(priceFeed); // F:[PO-3]

    if (skipCheck) value |= SKIP_PRICE_CHECK_FLAG; // F:[PO-3]

    _priceFeeds[token] = value + (uint256(decimals) << DECIMALS_SHIFT); // F:[PO-3]
  }

  // Admin functions
  function recoverFunds() external onlyOwner {
    SafeERC20.safeTransfer(
      IERC20(link),
      configuration.protocolTreasury(),
      IERC20(link).balanceOf(address(this))
    );
  }
}

