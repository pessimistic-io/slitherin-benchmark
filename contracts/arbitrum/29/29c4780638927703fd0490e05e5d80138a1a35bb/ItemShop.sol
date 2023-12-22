//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ItemShopSettings.sol";

contract ItemShop is Initializable, ItemShopSettings {

    function initialize() external initializer {
        ItemShopSettings.__ItemShopSettings_init();
    }

    function purchaseItems(
        uint256[] calldata _itemIds,
        uint256[] calldata _quantities)
    external
    whenNotPaused
    onlyEOA
    contractsAreSet
    nonZeroLength(_itemIds)
    {
        require(_itemIds.length == _quantities.length, "ItemShop: Bad array lengths");

        for(uint256 i = 0; i < _itemIds.length; i++) {
            _purchaseItem(_itemIds[i], _quantities[i]);
        }

        if(userToTotalItemsPurchased[msg.sender] >= 1) {
            badgez.mintIfNeeded(msg.sender, firstItemPurchaseBadgeId);
        }
        if(userToTotalItemsPurchased[msg.sender] >= 100) {
            badgez.mintIfNeeded(msg.sender, hundrethItemPurchaseBadgeId);
        }
    }

    function _purchaseItem(uint256 _itemId, uint256 _quantity) private {
        ItemListing storage _itemListing = itemIdToListing[_itemId];

        require(_itemListing.listingStart > 0, "ItemShop: No active listing for this item");
        require(_itemListing.quantityAvailable == 0
            || _itemListing.quantityPurchased + _quantity <= _itemListing.quantityAvailable,
            "ItemShop: Exceeds quantity available");
        require(block.timestamp >= _itemListing.listingStart, "ItemShop: Listing is not active yet");
        require(_itemListing.listingEnd == 0 || block.timestamp < _itemListing.listingEnd, "ItemShop: Listing is no longer active");
        require(_quantity > 0, "ItemShop: Zero quantity");

        _itemListing.quantityPurchased += _quantity;

        userToTotalItemsPurchased[msg.sender] += _quantity;

        uint256 _totalBugzRequired = _itemListing.bugzCost * _quantity;

        bugz.burn(msg.sender, _totalBugzRequired);

        itemz.mint(msg.sender, _itemId, _quantity);

        emit ItemPurchased(_itemId, _quantity);
    }
}
