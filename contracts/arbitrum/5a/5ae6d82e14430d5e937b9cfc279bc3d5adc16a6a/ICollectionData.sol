// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ICollectionData {
    
    enum CollectionType {
        ANY,
        PASSPORT,
        OFFER,
        COLLECTION,
        BADGE,
        EVENT
    }

    enum OfferType {
        NOTANOFFER,
        FEATURED,
        REGULAR 
    }

    enum MintModel {
        REGULAR,
        SUBSCRIPTION
    }

    struct CollectionData {

        // A collectible may optionally be linked to an entity
        // If its not then this will be address(0)
        address entity;

        // Flag that checks if a collectible should be minted when a collectible which it is linked to is minted
        // Eg: Offers/Events that should be airdropped along with passport for them
        // If true for a linked collectible, mintLinked can be called by the
        // dispatcher contract to mint collectibles linked to it
        bool mintWithLinked;

        // Price per collectible in this collection.
        // 6 decimals precision 24494022 = 24.494022 USD
        uint256 price;

        // Max Purchase limit for this collection.
        uint256 maxPurchase;

        // Start time from when the Collection will be on offer to patrons
        // Zero for non-time bound
        uint256 start;

        // End time from when the Collection will no longer be available for purchase
        // Zero for non-time bound
        uint256 end;

        // Flag to indicate the need for check in to place an order
        bool checkInNeeded;

        // Maximum tokens that can be minted for this collection
        // Used for passports
        // Zero for unlimited
        uint256 maxMint;

        // Type of offer represented by the collection(NOTANOFFER for passports and other collections)
        OfferType offerType;

        // Non zero when the collection needs some criteria to be fulfilled on a passport
        address passport;

        // Min reward balance needed to get a collectible of this collection airdropped
        int256 minRewardBalance;

        // Min visits needed to get a collectible this collection airdropped
        uint256 minVisits;

        // Min friend visits needed to get a collectible this collection airdropped
        uint256 minFriendVisits;

        // Storage Gap
        uint256[20] __gap;

    }

    struct CollectionDataAdditional {
        // Max Balance a patron can hold for this collection.
        // Zero for 1
        uint256 maxBalance;

        // Is minted only when a linked collection is minted
        bool mintWithLinkedOnly;

        uint256 isCoupon; //zero = false, nonzero = true.

        MintModel mintModel; // The mint model for the collection. REGULAR, SUBSCRIPTION, etc.

        // Storage Gap
        uint256[17] __gap;
    }

    struct CollectibleDetails {
        uint256 id;
        uint256 mintTime; // timestamp
        bool isActive;
        int256 rewardBalance; // used for passports only
        uint256 visits; // // used for passports only
        uint256 friendVisits; // used for passports only
        // A flag indicating whether the collectible was redeemed
        // This can be useful in scenarios such as cancellation of orders
        // where the the collectible minted to patron is supposed to be burnt/demarcated
        // in some way when the payment is reversed to patron
        bool redeemed;

        // Storage Gap
        uint256[20] __gap;
    }

} 
