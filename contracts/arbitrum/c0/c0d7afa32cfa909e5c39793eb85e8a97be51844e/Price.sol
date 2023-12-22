// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.3;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./AggregatorV3Interface.sol";

/// @title Abstract Price Contract
/// @notice Handles the hassles of calculating the same price formula for each xAsset
/// @dev Not deployable. This has to be implemented by any xAssetPrice contract
abstract contract Price {
    using SafeMath for uint256;

    /// @dev Specify the underlying asset of each xAssetPrice contract
    address public underlyingAssetAddress;
    address public underlyingPriceFeedAddress;
    address public usdcPriceFeedAddress;

    uint256 internal assetPriceDecimalMultiplier;
    uint256 internal usdcPriceDecimalMultiplier;

    uint256 private constant FACTOR = 1e18;
    uint256 private constant PRICE_DECIMALS_CORRECTION = 1e12;

    /// @notice Provides the amount of the underyling assets of xAsset held by the xAsset asset in wei
    function getAssetHeld() public view virtual returns (uint256);

    /// @notice Anyone can know how much certain xAsset is worthy in USDC terms
    /// @dev This relies on the getAssetHeld function implemented by each xAssetPrice contract
    /// @dev Prices are handling 12 decimals
    /// @return capacity (uint256) How much an xAsset is worthy on USDC terms
    function getPrice() external view returns (uint256) {
        uint256 assetHeld = getAssetHeld();
        uint256 assetTotalSupply = IERC20(underlyingAssetAddress).totalSupply();

        (
            uint80 roundIDUsd,
            int256 assetUsdPrice,
            ,
            uint256 timeStampUsd,
            uint80 answeredInRoundUsd
        ) = AggregatorV3Interface(underlyingPriceFeedAddress).latestRoundData();
        require(timeStampUsd != 0, "ChainlinkOracle::getLatestAnswer: round is not complete");
        require(answeredInRoundUsd >= roundIDUsd, "ChainlinkOracle::getLatestAnswer: stale data");
        uint256 usdPrice = assetHeld.mul(uint256(assetUsdPrice)).mul(assetPriceDecimalMultiplier).div(assetTotalSupply);

        (
            uint80 roundIDUsdc,
            int256 usdcusdPrice,
            ,
            uint256 timeStampUsdc,
            uint80 answeredInRoundUsdc
        ) = AggregatorV3Interface(usdcPriceFeedAddress).latestRoundData();
        require(timeStampUsdc != 0, "ChainlinkOracle::getLatestAnswer: round is not complete");
        require(answeredInRoundUsdc >= roundIDUsdc, "ChainlinkOracle::getLatestAnswer: stale data");
        uint256 usdcPrice = usdPrice.mul(PRICE_DECIMALS_CORRECTION).div(uint256(usdcusdPrice)).div(
            usdcPriceDecimalMultiplier
        );
        return usdcPrice;
    }
}

