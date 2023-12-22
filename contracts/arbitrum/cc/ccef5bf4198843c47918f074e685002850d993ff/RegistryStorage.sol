// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Accountant } from "./Accountant.sol";
import { Transport } from "./Transport.sol";
import { ExecutorIntegration } from "./IExecutor.sol";

import { IntegrationDataTracker } from "./IntegrationDataTracker.sol";
import { GmxConfig } from "./GmxConfig.sol";

import { ILayerZeroEndpoint } from "./ILayerZeroEndpoint.sol";

library RegistryStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256('valio.storage.Registry');

    struct VaultSettings {
        bool canChangeManager;
        // The number of assets that can be active at once for a vault
        // This is important so withdraw processing doesn't consume > max gas
        uint maxActiveAssets;
        uint depositLockupTime;
        uint livelinessThreshold;
    }

    enum AssetType {
        Erc20,
        GMX
    }

    struct Layout {
        uint16 chainId;
        address protocolTreasury;
        address parentVaultDiamond;
        address childVaultDiamond;
        mapping(address => bool) parentVaults;
        mapping(address => bool) childVaults;
        VaultSettings vaultSettings;
        Accountant accountant;
        Transport transport;
        IntegrationDataTracker integrationDataTracker;
        GmxConfig gmxConfig;
        mapping(ExecutorIntegration => address) executors;
        // Price get will revert if the price hasn't be updated in the below time
        uint256 chainlinkTimeout;
        mapping(AssetType => address) valuers;
        mapping(AssetType => address) redeemers;
        mapping(address => AssetType) assetTypes;
        mapping(address => address) priceAggregators; // All must return USD price and be 8 decimals
        mapping(address => bool) deprecatedAssets; // Assets that cannot be traded into, only out of
        address zeroXExchangeRouter;
        uint zeroXMaximumSingleSwapPriceImpactBasisPoints;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;

        assembly {
            l.slot := slot
        }
    }
}

