// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./AggregatorV3Interface.sol";
import "./IPriceFeedAdapter.sol";
import "./UnlimitedPriceFeedUpdater.sol";
import "./Constants.sol";
import "./UnlimitedOwnable.sol";

/**
 * @title Unlimited Price Feed Adapter
 * @notice Gets the price data from the trusted Unlimited Leverage source.
 * @dev
 * The price is defined in token vs token price (e.g. ETH/USDC)
 * The Unlimited price has to be within a relative margin of the Chainlink one.
 * This acts as an additional price selfcheck with an external price feed source.
 * Limitation of this price feed is that Unlimited price, Chainlink asset and
 * Chainlink collateral price needs to be the same. This is done for optimization
 * puprposes as most Chainlink USD pairs have 8 decimals
 */
contract UnlimitedPriceFeedAdapter is UnlimitedPriceFeedUpdater, IPriceFeedAdapter, UnlimitedOwnable {
    /* ========== CONSTANTS ========== */

    /// @notice Minimum value that can be set for max deviation.
    uint256 constant MINIMUM_MAX_DEVIATION = 5;

    /* ========== STATE VARIABLES ========== */

    string public override name;
    AggregatorV3Interface public collateralChainlinkPriceFeed;
    AggregatorV3Interface public assetChainlinkPriceFeed;

    uint256 public immutable collateralDecimals;

    uint256 private immutable COLLATERAL_MULTIPLIER;
    uint256 private immutable COLLATERAL_TO_PRICE_MULTIPLIER;
    uint256 private assetPriceMultiplier;
    uint256 private collateralPriceMultiplier;

    uint256 public maxDeviation;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructs the UnlimitedPriceFeedAdapter contract.
     * @param controller_ The address of the controller contract.
     */
    constructor(uint256 collateralDecimals_, IController controller_, IUnlimitedOwner unlimitedOwner_)
        UnlimitedPriceFeedUpdater(controller_)
        UnlimitedOwnable(unlimitedOwner_)
    {
        require(
            PRICE_DECIMALS >= collateralDecimals_,
            "UnlimitedPriceFeedAdapter::constructor: price decimals must be >= collateral decimals"
        );

        collateralDecimals = collateralDecimals_;

        COLLATERAL_MULTIPLIER = 10 ** collateralDecimals_;
        COLLATERAL_TO_PRICE_MULTIPLIER = PRICE_MULTIPLIER / COLLATERAL_MULTIPLIER;
    }

    /**
     * @notice Initializes the name of the price feed adapter and underlying updater
     * @param name_ The name of the price feed adapter.
     * @param maxDeviation_ The maximum deviation of the Unlimited price from the Chainlink price.
     * @param collateralChainlinkPriceFeed_ The address of the Chainlink price feed for the collateral, needed for usd price.
     * @param assetChainlinkPriceFeed_ The address of the Chainlink price feed for the asset, needed for usd price.
     */
    function initialize(
        string calldata name_,
        uint256 maxDeviation_,
        AggregatorV3Interface collateralChainlinkPriceFeed_,
        AggregatorV3Interface assetChainlinkPriceFeed_
    ) external onlyOwner initializer {
        __UnlimitedPriceFeedUpdater_init(name_);

        name = name_;

        collateralChainlinkPriceFeed = collateralChainlinkPriceFeed_;
        assetChainlinkPriceFeed = assetChainlinkPriceFeed_;
        assetPriceMultiplier = 10 ** assetChainlinkPriceFeed_.decimals();
        collateralPriceMultiplier = 10 ** collateralChainlinkPriceFeed_.decimals();

        _updateMaxDeviation(maxDeviation_);
    }

    /* ============ ASSET - COLLATERAL CONVERSION ============ */

    /**
     * @notice Returns max asset equivalent to the collateral amount
     * @param collateralAmount_ the amount of collateral
     */
    function collateralToAssetMax(uint256 collateralAmount_) external view returns (uint256) {
        return _collateralToAsset(collateralAmount_);
    }

    /**
     * @notice Returns min asset equivalent to the collateral amount
     * @param collateralAmount_ the amount of collateral
     */
    function collateralToAssetMin(uint256 collateralAmount_) external view returns (uint256) {
        return _collateralToAsset(collateralAmount_);
    }

    function _collateralToAsset(uint256 collateralAmount_) private view returns (uint256) {
        return collateralAmount_ * COLLATERAL_TO_PRICE_MULTIPLIER * ASSET_MULTIPLIER / uint256(_price());
    }

    /**
     * @notice Returns maximum collateral equivalent to the asset amount
     * @param assetAmount_ the amount of asset
     */
    function assetToCollateralMax(uint256 assetAmount_) external view returns (uint256) {
        return _assetToCollateral(assetAmount_);
    }

    /**
     * @notice Returns minimum collateral equivalent to the asset amount
     * @param assetAmount_ the amount of asset
     */
    function assetToCollateralMin(uint256 assetAmount_) external view returns (uint256) {
        return _assetToCollateral(assetAmount_);
    }

    function _assetToCollateral(uint256 assetAmount_) private view returns (uint256) {
        return assetAmount_ * uint256(_price()) / COLLATERAL_TO_PRICE_MULTIPLIER / ASSET_MULTIPLIER;
    }

    /* ============ USD Conversion ============ */

    /**
     * @notice Returns the minimum usd equivalent to the asset amount
     * @dev The minimum collateral amount gets returned. It takes into accounts the minimum price.
     * NOTE: This price should not be used to calculate PnL of the trades
     * @param assetAmount_ the amount of asset
     * @return the amount of usd
     */
    function assetToUsdMin(uint256 assetAmount_) external view returns (uint256) {
        return _assetToUsd(assetAmount_);
    }

    /**
     * @notice Returns the maximum usd equivalent to the asset amount
     * @dev The maximum collateral amount gets returned. It takes into accounts the maximum price.
     * NOTE: This price should not be used to calculate PnL of the trades
     * @param assetAmount_ the amount of asset
     * @return the amount of usd
     */
    function assetToUsdMax(uint256 assetAmount_) external view returns (uint256) {
        return _assetToUsd(assetAmount_);
    }

    function _assetToUsd(uint256 assetAmount_) private view returns (uint256) {
        (, int256 answer,,,) = assetChainlinkPriceFeed.latestRoundData();
        return assetAmount_ * uint256(answer) / ASSET_MULTIPLIER;
    }

    /**
     * @notice Returns the minimum usd equivalent to the collateral amount
     * @dev The minimum collateral amount gets returned. It takes into accounts the minimum price.
     * NOTE: This price should not be used to calculate PnL of the trades
     * @param collateralAmount_ the amount of collateral
     * @return the amount of usd
     */
    function collateralToUsdMin(uint256 collateralAmount_) external view returns (uint256) {
        return _collateralToUsd(collateralAmount_);
    }

    /**
     * @notice Returns the maximum usd equivalent to the collateral amount
     * @dev The maximum collateral amount gets returned. It takes into accounts the maximum price.
     * NOTE: This price should not be used to calculate PnL of the trades
     * @param collateralAmount_ the amount of collateral
     * @return the amount of usd
     */
    function collateralToUsdMax(uint256 collateralAmount_) external view returns (uint256) {
        return _collateralToUsd(collateralAmount_);
    }

    function _collateralToUsd(uint256 collateralAmount_) private view returns (uint256) {
        (, int256 answer,,,) = collateralChainlinkPriceFeed.latestRoundData();
        return collateralAmount_ * uint256(answer) / COLLATERAL_MULTIPLIER;
    }

    /* ============ PRICE ============ */

    /**
     * @notice Returns the max price of the asset in the collateral
     * @dev Returns price of the last updated round
     */
    function markPriceMax() external view returns (int256) {
        return _price();
    }

    /**
     * @notice Returns the min price of the asset in the collateral
     * @dev Returns price of the last updated round
     */
    function markPriceMin() external view returns (int256) {
        return _price();
    }

    /**
     * @notice Updates the maximum deviation from the chainlink price feed.
     * @param maxDeviation_ The new maximum deviation.
     */
    function updateMaxDeviation(uint256 maxDeviation_) external onlyOwner {
        _updateMaxDeviation(maxDeviation_);
    }

    function _updateMaxDeviation(uint256 maxDeviation_) private {
        require(
            maxDeviation_ >= MINIMUM_MAX_DEVIATION && maxDeviation_ <= FULL_PERCENT,
            "UnlimitedPriceFeedAdapter::_updateMaxDeviation: Bad max deviation"
        );

        maxDeviation = maxDeviation_;
    }

    function _verifyNewPrice(int256 newPrice) internal view override {
        int256 chainlinkPrice = _getChainlinkPrice();

        unchecked {
            int256 maxAbsoluteDeviation = int256(uint256(chainlinkPrice) * maxDeviation / FULL_PERCENT);

            require(
                newPrice >= chainlinkPrice - maxAbsoluteDeviation && newPrice <= chainlinkPrice + maxAbsoluteDeviation,
                "UnlimitedPriceFeedAdapter::_verifyNewPrice: Price deviation too high"
            );
        }
    }

    function _getChainlinkPrice() internal view returns (int256) {
        (uint80 assetBaseRoundID, int256 assetAnswer,, uint256 assetBaseTimestamp, uint80 assetBaseAnsweredInRound) =
            assetChainlinkPriceFeed.latestRoundData();
        require(assetAnswer > 0, "UnlimitedPriceFeedAdapter::_getChainLinkPrice:assetChainlinkPriceFeed: answer <= 0");
        require(
            assetBaseAnsweredInRound >= assetBaseRoundID,
            "UnlimitedPriceFeedAdapter::_getChainLinkPrice:assetChainlinkPriceFeed: stale price"
        );
        require(
            assetBaseTimestamp > 0,
            "UnlimitedPriceFeedAdapter::_getChainLinkPrice:assetChainlinkPriceFeed: round not complete"
        );

        (
            uint80 collateralBaseRoundID,
            int256 collateralAnswer,
            ,
            uint256 collateralBaseTimestamp,
            uint80 collateralBaseAnsweredInRound
        ) = collateralChainlinkPriceFeed.latestRoundData();
        require(
            collateralAnswer > 0,
            "UnlimitedPriceFeedAdapter::_getChainLinkPrice:collateralChainlinkPriceFeed answer <= 0"
        );
        require(
            collateralBaseAnsweredInRound >= collateralBaseRoundID,
            "UnlimitedPriceFeedAdapter::_getChainLinkPrice:collateralChainlinkPriceFeed stale price"
        );
        require(
            collateralBaseTimestamp > 0,
            "UnlimitedPriceFeedAdapter::_getChainLinkPrice:collateralChainlinkPriceFeed Round not complete"
        );

        return assetAnswer * int256(PRICE_MULTIPLIER) * int256(collateralPriceMultiplier) / collateralAnswer
            / int256(assetPriceMultiplier);
    }
}

