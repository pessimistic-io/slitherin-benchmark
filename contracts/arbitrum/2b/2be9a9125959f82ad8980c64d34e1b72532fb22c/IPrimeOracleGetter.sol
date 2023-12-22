// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

/**
 * @title IPrimeOracleGetter
 * @author Prime
 * @notice Interface for the Prime price oracle.
 **/
interface IPrimeOracleGetter {

    /**
     * @dev Emitted after the price data feed of an asset is updated
     * @param asset The address of the asset
     * @param feed The price feed of the asset
     */
    event AssetFeedUpdated(uint256 chainId, address indexed asset, address indexed feed);

    /**
     * @notice Gets the price feed of an asset
     * @param asset The addresses of the asset
     * @return address of asset feed
     */
    function getAssetFeed(uint256 chainId, address asset) external view returns (address);

    /**
     * @notice Sets or replaces price feeds of assets
     * @param asset The addresses of the assets
     * @param feed The addresses of the price feeds
     */
    function setAssetFeed(uint256 chainId, address asset, address feed) external;

    /**
     * @notice Returns the price data in the denom currency
     * @param quoteToken A token to return price data for
     * @param denomToken A token to price quoteToken against
     * @param price of the asset from the oracle
     * @param decimals of the asset from the oracle
     **/
    function getAssetPrice(
        uint256 chainId,
        address quoteToken,
        address denomToken
    ) external view returns (uint256 price, uint8 decimals);

    /**
     * @notice Returns the price data in the denom currency
     * @param quoteToken A token to return price data for
     * @return return price of the asset from the oracle
     **/
    function getPriceDecimals(
        uint256 chainId,
        address quoteToken
    ) external view returns (uint256);

}

