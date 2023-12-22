// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;
import "./Ownable2StepUpgradeable.sol";
import "./EnumerableSet.sol";
import "./AggregatorV3Interface.sol";

import "./Checker.sol";
import "./SafeCast.sol";
import "./TokenUtils.sol";

import "./ISavvyPriceFeed.sol";

/// @title  SavvyPriceFeed
/// @author Savvy DeFi
contract SavvyPriceFeed is Ownable2StepUpgradeable, ISavvyPriceFeed {
    mapping(address => address) private priceFeeds;
    address public svyPriceFeed;
    uint256 public constant FIXED_POINT_SCALAR = 1e18;

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    /// @inheritdoc ISavvyPriceFeed
    function setPriceFeed(
        address baseToken,
        address priceFeed
    ) external override onlyOwner {
        Checker.checkArgument(
            baseToken != address(0),
            "zero base token address"
        );
        Checker.checkArgument(
            priceFeed != address(0),
            "zero price feed address"
        );
        priceFeeds[baseToken] = priceFeed;
    }

    /// @inheritdoc ISavvyPriceFeed
    function updateSvyPriceFeed(address newFeed) external override onlyOwner {
        Checker.checkArgument(newFeed != address(0), "zero price feed address");
        svyPriceFeed = newFeed;
    }

    /// @inheritdoc ISavvyPriceFeed
    function getBaseTokenPrice(
        address baseToken,
        uint256 amount
    ) external view override returns (uint256) {
        return _convertToUSD(baseToken, amount);
    }

    /// @inheritdoc ISavvyPriceFeed
    function getSavvyTokenPrice() external view override returns (uint256) {
        if (svyPriceFeed == address(0)) {
            return 0;
        }

        return _getChainlinkTokenPrice(svyPriceFeed);
    }

    /// @notice Get token price according to priceFeed.
    /// @param priceFeed_ The address of priceFeed on chainlink.
    /// @return Return token price calculated by 1e18.
    function _getChainlinkTokenPrice(
        address priceFeed_
    ) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeed_);
        (
            uint80 roundID,
            int price,
            ,
            uint256 timestamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        require(price > 0, "Chainlink price <= 0");
        require(answeredInRound >= roundID, "Stale price");
        require(timestamp != 0, "Round not complete");

        uint256 tokenPrice = uint256(price);
        uint8 decimals = priceFeed.decimals();
        uint8 additionDecimals = 18 - decimals;
        return tokenPrice * 10 ** additionDecimals;
    }

    /// @notice Convert amount of underlyint token to USD.
    /// @param baseToken_ The address of base token.
    /// @param amount_ The amount of base token.
    /// @return Converted amount of USD divided 10**decimals.
    function _convertToUSD(
        address baseToken_,
        uint256 amount_
    ) internal view returns (uint256) {
        address priceFeedAddr = priceFeeds[baseToken_];
        if (priceFeedAddr == address(0)) {
            return 0;
        }

        uint256 tokenPrice = _getChainlinkTokenPrice(priceFeedAddr);
        uint8 baseTokenDecimals = TokenUtils.expectDecimals(baseToken_);
        return (amount_ * tokenPrice) / 10 ** baseTokenDecimals;
    }

    uint256[100] private __gap;
}

