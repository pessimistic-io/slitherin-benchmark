// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Registry } from "./Registry.sol";
import { VaultParent } from "./VaultParent.sol";

import { IERC20 } from "./IERC20.sol";
import { ILayerZeroEndpoint } from "./ILayerZeroEndpoint.sol";

library DepositAutomatorStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256('valio.storage.DespositAutomator');

    // solhint-disable-next-line ordering
    struct QueuedDeposit {
        VaultParent vault;
        address depositor;
        uint tokenId;
        IERC20 depositAsset;
        uint depositAmount;
        uint maxUnitPrice;
        uint keeperFee;
        uint expiryTime;
        uint createdAtTime;
        uint nonce;
    }

    // solhint-disable-next-line ordering
    struct Layout {
        uint keeperFee;
        // Vault -> QueuedDeposit
        mapping(address => QueuedDeposit[]) queuedDepositsByVault;
        // Vault -> depositor -> QueuedDepositIndexes
        mapping(address => mapping(address => uint[])) queuedDepositIndexesByVaultByDepositor;
        // Vault -> depositor -> Completed QueuedDeposits
        mapping(address => mapping(address => QueuedDeposit[])) executedDepositsByVaultByDepositor;
        uint nonce;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;

        assembly {
            l.slot := slot
        }
    }
}

