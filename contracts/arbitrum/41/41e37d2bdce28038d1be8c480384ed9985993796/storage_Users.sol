/**
 * User-related storage for the YC Diamond.
 * Mainly used for analytical purposes of users,
 * and managing premium users
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Vault.sol";

// Represents a tier as a whole
struct Tier {
    bool isActive;
    uint256 powerLevel;
    uint256 monthlyCost;
    uint256 lifetimeCost;
}

/**
 * Represnts a user and it's current tier
 * if tier id == 0; no tier
 * @param tierId - The ID of the tier
 * @param endsOn - Timestamp of when this tier ends.
 */
struct UserTier {
    uint256 tierId;
    uint256 endsOn;
}

struct UsersStorage {
    /**
     * Map tier ID => Tier struct
     */
    mapping(uint256 tierID => Tier tier) tiers;
    /**
     * Increment this every time u classify a tier
     */
    uint256 tiersAmount;
    /**
     * Map user adddresses to their corresponding current tier
     */
    mapping(address user => UserTier currentTier) users;
    // The token address to pay with
    address paymentToken;
}

/**
 * The lib to use to retreive the storage
 */
library UsersStorageLib {
    // The namespace for the lib (the hash where its stored)
    bytes32 internal constant STORAGE_NAMESPACE =
        keccak256("diamond.yieldchain.storage.users");

    // Function to retreive our storage
    function retreive() internal pure returns (UsersStorage storage s) {
        bytes32 position = STORAGE_NAMESPACE;
        assembly {
            s.slot := position
        }
    }

    function getTiers() internal view returns (Tier[] memory tiers) {
        UsersStorage storage userStorage = retreive();
        uint256 tiersAmt = userStorage.tiersAmount;

        tiers = new Tier[](tiersAmt);

        for (uint256 i; i < tiers.length; i++) tiers[i] = userStorage.tiers[i];
    }

    function isInTier(
        address user,
        uint256 tierId
    ) internal view returns (bool isUserInTier) {
        UserTier memory userTier = retreive().users[user];
        Tier memory tier = retreive().tiers[tierId];
        Tier memory userCurrTier = retreive().tiers[userTier.tierId];

        if (
            userCurrTier.powerLevel >= tier.powerLevel &&
            block.timestamp < userTier.endsOn
        ) isUserInTier = true;
    }
}

