//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./MerkleProofUpgradeable.sol";

import "./ItemShopSettings.sol";

contract ItemShop is Initializable, ItemShopSettings {

    function initialize() external initializer {
        ItemShopSettings.__ItemShopSettings_init();
    }

    function purchaseItems(
        PurchaseItemParams[] calldata _purchases)
    external
    whenNotPaused
    onlyEOA
    contractsAreSet
    {
        require(_purchases.length > 0, "ItemShop: Bad array lengths");

        for(uint256 i = 0; i < _purchases.length; i++) {
            _purchaseItem(_purchases[i]);
        }

        if(userToTotalItemsPurchased[msg.sender] >= 1) {
            badgez.mintIfNeeded(msg.sender, firstItemPurchaseBadgeId);
        }
        if(userToTotalItemsPurchased[msg.sender] >= 100) {
            badgez.mintIfNeeded(msg.sender, hundrethItemPurchaseBadgeId);
        }
    }

    function _purchaseItem(PurchaseItemParams calldata _purchase) private {
        ItemListing storage _itemListing = itemIdToListing[_purchase.itemId];

        require(_itemListing.listingStart > 0, "ItemShop: No active listing for this item");
        require(_itemListing.quantityAvailable == 0
            || _itemListing.quantityPurchased + _purchase.quantity <= _itemListing.quantityAvailable,
            "ItemShop: Exceeds quantity available");
        require(block.timestamp >= _itemListing.listingStart, "ItemShop: Listing is not active yet");
        require(_itemListing.listingEnd == 0 || block.timestamp < _itemListing.listingEnd, "ItemShop: Listing is no longer active");
        require(_purchase.quantity > 0, "ItemShop: Zero quantity");

        if(_itemListing.merkleRoot != 0x0) {
            bytes32 _leaf = keccak256(abi.encodePacked(msg.sender, _purchase.amountAllowedForMerkle));

            require(
                MerkleProofUpgradeable.verify(_purchase.proof, _itemListing.merkleRoot, _leaf),
                "ItemShop: Proof invalid"
            );

            uint256 _amountPurchasedSoFar = listingIdToUserToNumberClaimed[_itemListing.listingId][msg.sender];
            require(_amountPurchasedSoFar + _purchase.quantity <= _purchase.amountAllowedForMerkle, "ItemShop: Bad quantity for merkle");

            listingIdToUserToNumberClaimed[_itemListing.listingId][msg.sender] += _purchase.quantity;
        }

        _itemListing.quantityPurchased += _purchase.quantity;

        userToTotalItemsPurchased[msg.sender] += _purchase.quantity;

        uint256 _totalBugzRequired = _itemListing.bugzCost * _purchase.quantity;

        bugz.burn(msg.sender, _totalBugzRequired);

        itemz.mint(msg.sender, _purchase.itemId, _purchase.quantity);

        emit ItemPurchased(_purchase.itemId, _purchase.quantity, _itemListing.listingId);
    }
}

struct PurchaseItemParams {
    uint64 itemId;
    uint64 quantity;
    uint64 amountAllowedForMerkle;
    bytes32[] proof;
}
