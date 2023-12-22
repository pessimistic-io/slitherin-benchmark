// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

/**
 * @title IOracleProxy
 * @author Amorphous
 * @notice Defines the basic interface for a Tazz price oracle proxy.
 **/
interface IOracleProxy {
    /**
     * @notice Returns the token0 currency
     * @return The address of the token0 contract
     **/
    function TOKEN0() external view returns (address);

    /**
     * @notice Returns the token1 currency
     * @return The address of the token1 contract
     **/
    function TOKEN1() external view returns (address);

    /**
     * @notice Returns the price source
     * @return The address of the price oracle
     **/
    function ORACLE_SOURCE() external view returns (address);

    /**
     * @notice Returns the base currency given the asset
     * @param asset is the address of the asset
     * @return The address of the base currency given the asset adress
     **/
    function getBaseCurrency(address asset) external view returns (address);

    /**
     * @notice Gets the avg tick of asset price vs base currency price
     * @return The avg price tick of the asset in base currency
     **/
    function getAvgTick(address asset, uint32 lookbackPeriod) external view returns (int24);
}

