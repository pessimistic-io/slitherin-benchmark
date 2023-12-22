// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.3;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./Initializable.sol";
import "./AggregatorV3Interface.sol";

/// @title Native Token Market Price Contract
contract NativePrice is Initializable {
    using SafeMath for uint256;

    address public underlyingAssetAddress;
    address public underlyingPriceFeedAddress;
    address public usdcPriceFeedAddress;

    uint256 internal assetPriceDecimalMultiplier;
    uint256 internal usdcPriceDecimalMultiplier;

    uint256 private constant FACTOR = 1e18;
    uint256 private constant PRICE_DECIMALS_CORRECTION = 1e12;

    /// @notice Upgradeable smart contract constructor
    /// @dev Just provide the addresses of the price feeders
    /// @param _underlyingAssetAddress (address) Native asset address
    /// @param _underlyingPriceFeedAddress (address) ChainLink NATIVE-USD aggregator address
    /// @param _usdcPriceFeedAddress (address) ChainLink USDC-USD aggregator address
    function initialize(
        address _underlyingAssetAddress,
        address _underlyingPriceFeedAddress,
        address _usdcPriceFeedAddress
    ) external initializer {
        require(_underlyingAssetAddress != address(0));
        require(_underlyingPriceFeedAddress != address(0));
        require(_usdcPriceFeedAddress != address(0));
        underlyingAssetAddress = _underlyingAssetAddress;
        underlyingPriceFeedAddress = _underlyingPriceFeedAddress;
        usdcPriceFeedAddress = _usdcPriceFeedAddress;

        uint256 assetDecimals = AggregatorV3Interface(underlyingPriceFeedAddress).decimals(); // Depends on the aggregator decimals. Chainlink usually uses 12 decimals
        uint256 usdcDecimals = AggregatorV3Interface(usdcPriceFeedAddress).decimals();
        assetPriceDecimalMultiplier = 10**(uint256(18).sub(assetDecimals));
        usdcPriceDecimalMultiplier = 10**(uint256(18).sub(usdcDecimals));
    }

    /// @notice Anyone can know how much certain underlying asset is worthy in USDC terms
    /// @dev Prices are handling 12 decimals
    /// @return capacity (uint256) How much an underlying asset is worthy on USDC terms
    function getPrice() external view returns (uint256) {
        (
            uint80 roundIDUsd,
            int256 assetUsdPrice,
            ,
            uint256 timeStampUsd,
            uint80 answeredInRoundUsd
        ) = AggregatorV3Interface(underlyingPriceFeedAddress).latestRoundData();
        require(timeStampUsd != 0, "ChainlinkOracle::getLatestAnswer: round is not complete");
        require(answeredInRoundUsd >= roundIDUsd, "ChainlinkOracle::getLatestAnswer: stale data");

        (
            uint80 roundIDUsdc,
            int256 usdcusdPrice,
            ,
            uint256 timeStampUsdc,
            uint80 answeredInRoundUsdc
        ) = AggregatorV3Interface(usdcPriceFeedAddress).latestRoundData();
        require(timeStampUsdc != 0, "ChainlinkOracle::getLatestAnswer: round is not complete");
        require(answeredInRoundUsdc >= roundIDUsdc, "ChainlinkOracle::getLatestAnswer: stale data");
        uint256 usdcPrice = uint256(assetUsdPrice)
            .mul(assetPriceDecimalMultiplier)
            .mul(PRICE_DECIMALS_CORRECTION)
            .div(uint256(usdcusdPrice))
            .div(usdcPriceDecimalMultiplier);
        return usdcPrice;
    }
}

