// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Registry } from "./Registry.sol";

import { VaultRiskProfile } from "./IVaultRiskProfile.sol";

library VaultBaseStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256('valio.storage.VaultBase');

    struct Layout {
        Registry registry;
        address manager;
        address[] assets;
        mapping(address => bool) enabledAssets;
        VaultRiskProfile riskProfile;
        bytes32 vaultId;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;

        assembly {
            l.slot := slot
        }
    }
}

