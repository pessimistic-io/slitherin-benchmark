// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Registry } from "./Registry.sol";
import { VaultParent } from "./VaultParent.sol";
import { ILayerZeroEndpoint } from "./ILayerZeroEndpoint.sol";

library WithdrawAutomatorStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256('valio.storage.WithdrawAutomator');

    // solhint-disable-next-line ordering
    struct QueuedWithdraw {
        VaultParent vault;
        uint tokenId;
        uint shares;
        uint minUnitPrice;
        uint keeperFee;
        uint[] lzFees;
        uint totalLzFee;
        uint expiryTime;
        uint createdAtTime;
    }

    // solhint-disable-next-line ordering
    struct Layout {
        uint keeperFee;
        uint lzFeeBufferBasisPoints;
        // Vault -> QueuedWithdraw
        mapping(address => QueuedWithdraw[]) queuedWithdrawsByVault;
        // Vault -> tokenId -> QueuedWithdrawIndexes
        mapping(address => mapping(uint => uint[])) queuedWithdrawIndexesByVaultByTokenId;
        // Vault -> tokenId -> Completed QueuedWithdraws
        mapping(address => mapping(uint => QueuedWithdraw[])) executedWithdrawsByVaultByTokenId;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;

        assembly {
            l.slot := slot
        }
    }
}

