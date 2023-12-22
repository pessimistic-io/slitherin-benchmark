// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AppStorage, LibAppStorage, Modifiers} from "./LibAppStorage.sol";

import {FacetCommons} from "./FacetCommons.sol";
import {IERC20Extended} from "./IERC20Extended.sol";
import {IERC721Extended} from "./IERC721Extended.sol";



// return on chain metadata with latest evolution svgs
contract ManagerFacet is FacetCommons, Modifiers {
    function setDiamondAddress(address _diamondAddress) external onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();

        s.DIAMOND_ADDRESS = _diamondAddress;
    }

    function setNFTAddress(IERC721Extended _nft) external onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();

        s.nft = _nft;
    }

    function setTokenAddress(IERC721Extended _token) external onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();

        s.nft = _token;
    }

    
    event ItemCreated(uint256 id, string name, uint256 price, uint256 points, uint256 timeExtension, uint256 equipExpires, bool isSellable, uint256 supply);
    event ItemUpdated(uint256 id, string name, uint256 price, uint256 points, uint256 timeExtension, uint256 equipExpires, bool isSellable, uint256 supply);

    function createItem(string memory name, uint256 price, uint256 points, uint256 timeExtension, uint256 equipExpires, bool isSellable, uint256 supply) external onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        uint256 newItemId = s._itemIds;

        s.itemName[newItemId] = name;
        s.itemPrice[newItemId] = price;
        s.itemPoints[newItemId] = points;
        s.itemTimeExtension[newItemId] = timeExtension;
        s.itemEquipExpires[newItemId] = equipExpires;
        s.itemIsSellable[newItemId] = isSellable;
        s.itemSupply[newItemId] = supply;

        s._itemIds++;

        emit ItemCreated(newItemId, name, price, points, timeExtension, equipExpires, isSellable, supply);
    }

    function updateItem(uint256 id, string memory name, uint256 price, uint256 points, uint256 timeExtension, uint256 equipExpires, bool isSellable, uint256 supply) external onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();

        s.itemName[id] = name;
        s.itemPrice[id] = price;
        s.itemPoints[id] = points;
        s.itemTimeExtension[id] = timeExtension;
        s.itemEquipExpires[id] = equipExpires;
        s.itemIsSellable[id] = isSellable;
        s.itemSupply[id] = supply;

        emit ItemUpdated(id, name, price, points, timeExtension, equipExpires, isSellable, supply);
    }

    function updateLevelList(uint256[] memory _levelList) external onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        s.levelList = _levelList;
    }
}
