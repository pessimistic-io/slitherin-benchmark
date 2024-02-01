// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import { IERC20 } from "./IERC20.sol";
import { IAToken } from "./IAToken.sol";
import {     IAaveLendingPool } from "./IAaveLendingPool.sol";
import {     IAaveLendingPoolAddressesProvider } from "./IAaveLendingPoolAddressesProvider.sol";

// Libraries
import {     EnumerableSet } from "./EnumerableSet.sol";

// Storage
import { MarketStorageLib, MarketStorage } from "./market.sol";
import { AppStorageLib } from "./app.sol";

library LibDapps {
    function s() internal pure returns (MarketStorage storage) {
        return MarketStorageLib.store();
    }

    /**
        @notice Grabs the Aave lending pool instance from the Aave lending pool address provider.
        @param aaveLPAddressProvider The immutable address of Aave's Lending Pool Address Provider on the deployed network.
        @return IAaveLendingPool instance address.
     */
    function getAaveLendingPool(address aaveLPAddressProvider)
        internal
        view
        returns (IAaveLendingPool)
    {
        return
            IAaveLendingPool(
                IAaveLendingPoolAddressesProvider(aaveLPAddressProvider)
                    .getLendingPool()
            ); // LP address provider contract is immutable on each deployed network and the address will never change
    }

    /**
        @notice Grabs the aToken instance from the lending pool.
        @param aaveLPAddressProvider The immutable address of Aave's Lending Pool Address Provider on the deployed network.
        @param tokenAddress The underlying asset address to get the aToken for.
        @return IAToken instance.
     */
    function getAToken(address aaveLPAddressProvider, address tokenAddress)
        internal
        view
        returns (IAToken)
    {
        return
            IAToken(
                getAaveLendingPool(aaveLPAddressProvider).getReserveData(
                    tokenAddress
                ).aTokenAddress
            );
    }
}

