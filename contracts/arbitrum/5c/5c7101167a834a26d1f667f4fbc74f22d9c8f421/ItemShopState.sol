//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./IBugz.sol";
import "./IItemz.sol";
import "./IBadgez.sol";
import "./IItemShop.sol";
import "./AdminableUpgradeable.sol";

abstract contract ItemShopState is Initializable, IItemShop, AdminableUpgradeable {

    event ListingChanged(uint256 _itemId, ItemListing _listing);
    event ListingRemoved(uint256 _itemId, uint256 _listingId);
    event ItemPurchased(uint256 _itemId, uint256 _quantity, uint256 _listingId);

    IBugz public bugz;
    IItemz public itemz;
    IBadgez public badgez;

    uint256 firstItemPurchaseBadgeId;
    uint256 hundrethItemPurchaseBadgeId;

    mapping(uint256 => ItemListing) public itemIdToListing;
    mapping(address => uint256) public userToTotalItemsPurchased;

    uint256 public listingId;

    mapping(uint256 => mapping(address => uint256)) public listingIdToUserToNumberClaimed;

    function __ItemShopState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        firstItemPurchaseBadgeId = 7;
        hundrethItemPurchaseBadgeId = 8;
    }
}

struct ItemListing {
    // If 0, no limit.
    uint256 quantityAvailable;
    uint256 quantityPurchased;
    // If set to 0, this listing will be considered non-existent.
    uint256 listingStart;
    // If 0, no end.
    uint256 listingEnd;
    uint256 bugzCost;
    // A unique identifier for this listing. Allows for linking to a specific set of processed "proofs"
    //
    uint256 listingId;
    // If set, this item listing is a whitelist.
    bytes32 merkleRoot;
}
