// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SolidStateDiamond.sol";
import "./ERC20MetadataStorage.sol";
import "./IERC20Metadata.sol";
import "./ERC4626BaseStorage.sol";

import "./IPremiaPool.sol";

import "./VaultStorage.sol";

/**
 * @title Knox Vault Diamond Contract
 * @dev implements EIP2535 Diamond Standard
 * @dev contracts are upgradable
 */

contract VaultDiamond is SolidStateDiamond {
    using ERC20MetadataStorage for ERC20MetadataStorage.Layout;
    using ERC4626BaseStorage for ERC4626BaseStorage.Layout;
    using OwnableStorage for OwnableStorage.Layout;
    using VaultStorage for VaultStorage.Layout;

    constructor(VaultStorage.InitProxy memory initProxy) {
        address asset;

        {
            VaultStorage.Layout storage l = VaultStorage.layout();

            IPremiaPool.PoolSettings memory settings =
                IPremiaPool(initProxy.pool).getPoolSettings();

            l.isCall = initProxy.isCall;
            asset = l.isCall ? settings.underlying : settings.base;

            l.baseDecimals = IERC20Metadata(settings.base).decimals();
            l.underlyingDecimals = IERC20Metadata(settings.underlying)
                .decimals();

            l.delta64x64 = initProxy.delta64x64;
            l.reserveRate64x64 = initProxy.reserveRate64x64;
            l.performanceFee64x64 = initProxy.performanceFee64x64;

            l.Pricer = IPricer(initProxy.pricer);
            l.feeRecipient = initProxy.feeRecipient;
            l.keeper = initProxy.keeper;

            l.startOffset = 8 hours;
            l.endOffset = 8.5 hours;
        }

        {
            ERC20MetadataStorage.Layout storage l =
                ERC20MetadataStorage.layout();
            l.setName(initProxy.name);
            l.setSymbol(initProxy.symbol);
            l.setDecimals(18);
        }

        ERC4626BaseStorage.layout().asset = asset;
        OwnableStorage.layout().setOwner(msg.sender);
    }
}

