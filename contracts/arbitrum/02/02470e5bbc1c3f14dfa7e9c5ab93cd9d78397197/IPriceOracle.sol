// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

interface IPriceOracle {
    struct PriceOracleConstructorParams {
        address weth;
        PriceRegistryInputParams[] assetToUSD;
        PriceRegistryInputParams[] assetToETH;
    }

    struct PriceRegistryInputParams {
        address underlying;
        address registry;
    }

    function addUnderlyingRegistry(
        address underlying,
        address registry,
        bool isUSD
    ) external;

    function removeUnderlyingRegistry(address underlying, bool isUSD) external;

    function getUSDPriceByUnderlying(address underlying)
        external
        view
        returns (uint256);

    function getETHPriceByUnderlying(address underlying)
        external
        view
        returns (uint256);

    event SetInterval(uint256 o, uint256 n);
    event AddUnderlyingRegistry(address, address);
    event RemoveUnderlyingRegistry(address, address);
}

