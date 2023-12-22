//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ItemShopContracts.sol";

abstract contract ItemShopSettings is Initializable, ItemShopContracts {

    function __ItemShopSettings_init() internal initializer {
        ItemShopContracts.__ItemShopContracts_init();
    }

    function addListings(
        uint256[] calldata _itemIds,
        ItemListing[] calldata _listings)
    external
    contractsAreSet
    onlyAdminOrOwner
    {
        require(_itemIds.length == _listings.length, "ItemShop: Bad array lengths");

        for(uint256 i = 0; i < _itemIds.length; i++) {
            _addListing(_itemIds[i], _listings[i]);
        }
    }

    function _addListing(uint256 _itemId, ItemListing calldata _listing) private {
        require(_itemId > 0, "ItemShop: Bad item ID");
        require(_listing.listingStart > 0, "ItemShop: Bad start time");
        require(_listing.bugzCost > 0, "ItemShop: Bugz price not set");

        itemIdToListing[_itemId] = _listing;

        emit ListingChanged(_itemId, _listing);
    }

    function removeListings(
        uint256[] calldata _itemIds)
    external
    contractsAreSet
    onlyAdminOrOwner
    {
        for(uint256 i = 0; i < _itemIds.length; i++) {
            // Effectively removes the listing.
            itemIdToListing[_itemIds[i]].listingStart = 0;

            emit ListingRemoved(_itemIds[i]);
        }
    }

    function hasListingForItem(uint256 _itemId) external view returns(bool) {
        return itemIdToListing[_itemId].listingStart > 0;
    }
}
