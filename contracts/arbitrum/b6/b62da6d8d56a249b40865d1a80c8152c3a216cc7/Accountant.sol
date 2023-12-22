// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { AddressUtils } from "./AddressUtils.sol";

import { Registry } from "./Registry.sol";
import { VaultBaseExternal } from "./VaultBaseExternal.sol";
import { IAggregatorV3Interface } from "./IAggregatorV3Interface.sol";
import { IValuer } from "./IValuer.sol";

import { Constants } from "./Constants.sol";

contract Accountant {
    using AddressUtils for address;

    Registry registry;

    constructor(address _registry) {
        require(_registry != address(0), 'Invalid registry');
        registry = Registry(_registry);
    }

    function isSupportedAsset(address asset) external view returns (bool) {
        return registry.valuers(asset) != address(0);
    }

    function isDeprecated(address asset) public view returns (bool) {
        return registry.deprecatedAssets(asset);
    }

    function getVaultValue(address vault) external view returns (uint value) {
        address[] memory activeAssets = VaultBaseExternal(vault)
            .assetsWithBalances();
        for (uint i = 0; i < activeAssets.length; i++) {
            value += assetValueOfVault(activeAssets[i], vault);
        }
    }

    function assetValueOfVault(
        address asset,
        address vault
    ) public view returns (uint) {
        int256 unitPrice = getUSDPrice(asset);
        address valuer = registry.valuers(asset);
        require(valuer != address(0), 'No valuer');
        return IValuer(valuer).getVaultValue(vault, asset, unitPrice);
    }

    function assetValue(address asset, uint amount) public view returns (uint) {
        int256 unitPrice = getUSDPrice(asset);
        address valuer = registry.valuers(asset);
        require(valuer != address(0), 'No valuer');
        return IValuer(valuer).getAssetValue(amount, asset, unitPrice);
    }

    function getUSDPrice(address asset) public view returns (int256 price) {
        address aggregator = registry.priceAggregators(asset);

        require(aggregator != address(0), 'No Price aggregator');
        uint256 updatedAt;
        (, price, , updatedAt, ) = IAggregatorV3Interface(aggregator)
            .latestRoundData();

        require(
            updatedAt + registry.chainlinkTimeout() >= block.timestamp,
            'Price expired'
        );

        require(price > 0, 'Price not available');

        price = price * (int(Constants.VAULT_PRECISION) / 10 ** 8);
    }
}

