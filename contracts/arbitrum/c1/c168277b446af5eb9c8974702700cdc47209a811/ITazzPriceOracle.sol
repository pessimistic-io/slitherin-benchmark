// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IGuildAddressesProvider} from "./IGuildAddressesProvider.sol";

/**
 * @title ITazzPriceOracle
 * @author Amorphous
 * @notice Defines the basic interface for a Tazz price oracle.
 **/
interface ITazzPriceOracle {
    /**
     * @notice Returns the GuildAddressesProvider
     * @return The address of the GuildAddressesProvider contract
     */
    function ADDRESSES_PROVIDER() external view returns (IGuildAddressesProvider);

    /**
     * @notice Returns the base currency address for the price oracle
     * @return The base currency address.
     **/
    function BASE_CURRENCY() external view returns (address);

    /**
     * @notice Sets the price source for each asset
     * @param assets The addresses of the assets
     * @param sources The addresses of the price sources for each asset
     **/
    function setAssetPriceSources(address[] memory assets, address[] memory sources) external;

    /**
     * @notice Gets the asset price in the base currency
     * @param asset The address of the asset
     * @return The price of the asset in the oracle base currency
     **/
    function getAssetPrice(address asset) external view returns (uint256);
}

