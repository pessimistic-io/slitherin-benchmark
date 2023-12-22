// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./IPrimeOracleGetter.sol";
import "./PrimeOracleStorage.sol";

/**
 * @title IPrimeOracle
 * @author Prime
 * @notice The core interface for the Prime Oracle
 */
abstract contract IPrimeOracle is PrimeOracleStorage {

    /**
     * @dev Emitted after the price data feed of an asset is set/updated
     * @param asset The address of the asset
     * @param chainId The chainId of the asset
     * @param feed The price feed of the asset
     */
    event SetPrimaryFeed(uint256 chainId, address indexed asset, address indexed feed);

    /**
     * @dev Emitted after the price data feed of an asset is set/updated
     * @param asset The address of the asset
     * @param feed The price feed of the asset
     */
    event SetSecondaryFeed(uint256 chainId, address indexed asset, address indexed feed);

    /**
     * @dev Emitted after the exchange rate data feed of a loan market asset is set/updated
     * @param asset The address of the asset
     * @param chainId The chainId of the asset
     * @param feed The price feed of the asset
     */
    event SetExchangRatePrimaryFeed(uint256 chainId, address indexed asset, address indexed feed);

    /**
     * @dev Emitted after the exchange rate data feed of a loan market asset is set/updated
     * @param asset The address of the asset
     * @param feed The price feed of the asset
     */
    event SetExchangeRateSecondaryFeed(uint256 chainId, address indexed asset, address indexed feed);

    /**
     * @notice Get the underlying price of a cToken asset
     * @param collateralMarketUnderlying The PToken collateral to get the sasset price of
     * @param chainId the chainId to get an asset price for
     * @return The underlying asset price.
     *  Zero means the price is unavailable.
     */
    function getUnderlyingPrice(uint256 chainId, address collateralMarketUnderlying) external view virtual returns (uint256, uint8);

    /**
     * @notice Get the underlying borrow price of loanMarketAsset
     * @return The underlying borrow price
     *  Zero means the price is unavailable.
     */
    function getUnderlyingPriceBorrow(
        uint256 chainId,
        address loanMarketUnderlying
    ) external view virtual returns (uint256, uint8);

    /**
     * @notice Get the exchange rate of loanMarketAsset to basis
     * @return The underlying exchange rate of loanMarketAsset to basis
     *  Zero means the price is unavailable.
     */
    function getBorrowAssetExchangeRate(
        address loanMarketOverlying,
        uint256 loanMarketOverlyingChainId,
        address loanMarketUnderlying,
        uint256 loanMarketUnderlyingChainId
    ) external view virtual returns (uint256 /* ratio */, uint8 /* decimals */);

    /*** Admin Functions ***/

    /**
     * @notice Sets or replaces price feeds of assets
     * @param asset The addresses of the assets
     * @param feed The addresses of the price feeds
     */
    function setPrimaryFeed(uint256 chainId, address asset, IPrimeOracleGetter feed) external virtual;

    /**
     * @notice Sets or replaces price feeds of assets
     * @param asset The addresses of the assets
     * @param feed The addresses of the price feeds
     */
    function setSecondaryFeed(uint256 chainId, address asset, IPrimeOracleGetter feed) external virtual;
}

