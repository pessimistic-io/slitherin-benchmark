// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AppStorage, LibAppStorage, Modifiers} from "./LibAppStorage.sol";

import {LibMeta} from "./LibMeta.sol";

import {EnumerableMap} from "./EnumerableMap.sol";

import {FacetCommons} from "./FacetCommons.sol";

contract ShopFacet is FacetCommons, Modifiers {
    using EnumerableMap for EnumerableMap.UintToUintMap;

    event BuyItem(uint256 nftId, address giver, uint256 itemId);
    event SellItem(uint256 nftId, address giver, uint256 itemId);
    event NameChange(uint256 nftId, string name);

    // proof of concept
    function buyAccessory(
        uint256 _petId,
        uint256 _id
    ) external isApproved(_petId) {
        AppStorage storage s = LibAppStorage.appStorage();
        require(myFrenFacet().itemExists(_id), "This item doesn't exist");
        require(myFrenFacet().isPetAlive(_petId), "pet is dead"); //no revives

        uint256 amount = s.itemPrice[_id];
        uint256 refAmt = s.itemPrice[_id] / 10;

        s.token.transferFrom(msg.sender, address(this), amount);

        // if _id grater then 5 means not food.
        if (_id > 6) {
            if (!s.itemIsSellable[_id]) {
                s.token.burn(amount - refAmt);
            }
            equipItem(_petId, _id);
        } else {
            s.token.burn(amount - refAmt);
        }

        // recalculate time until starving
        if (s.itemTimeExtension[_id] > 0) {
            s.timeUntilStarving[_petId] =
                block.timestamp +
                s.itemTimeExtension[_id];
        }

        // update point systems
        updatePointsAndRewards(_petId, s.itemPoints[_id]);

        distributeToRef(_petId, refAmt);

        emit BuyItem(_petId, msg.sender, _id);
    }

    // allow users to sell back into the bonding curve
    function sellItem(uint256 _petId, uint256 _id) external isApproved(_petId) {
        AppStorage storage s = LibAppStorage.appStorage();

        require(s.itemIsSellable[_id], "!can't sell this item");

        EnumerableMap.UintToUintMap storage itemsOwned = s.itemsOwned[_petId];

        uint256 totalOwned = itemsOwned.get(_id);

        require(totalOwned > 0, "You don't own this item");

        // removes
        itemsOwned.set(_id, totalOwned - 1);

        (, , uint256 _sellPrice, , , , , , , ) = myFrenFacet().getItemInfo(
            _id
        );

        s.itemPrice[_id] -= s.itemDelta[_id];

        s.token.transfer(msg.sender, _sellPrice);

        s.itemBought[_id] -= 1;

        emit SellItem(_petId, msg.sender, _id);
    }

    function setPetName(
        uint256 _id,
        string memory _name
    ) external isApproved(_id) {
        AppStorage storage s = LibAppStorage.appStorage();

        s.petName[_id] = _name;

        emit NameChange(_id, _name);
    }
}
