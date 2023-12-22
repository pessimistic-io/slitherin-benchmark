//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./AdventureContracts.sol";

abstract contract AdventureSettings is Initializable, AdventureContracts {

     using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function __AdventureSettings_init() internal initializer {
        AdventureContracts.__AdventureContracts_init();
    }

    function addAdventure(
        string calldata _name,
        AdventureInfo calldata _adventureInfo,
        InputItem[] calldata _inputItems)
    external
    onlyAdminOrOwner
    {
        require(!isKnownAdventure(_name), "Adventure: Adventure already known");
        require(_adventureInfo.isInputRequired.length == _inputItems.length, "Adventure: Bad array lengths");

        nameToAdventureInfo[_name] = _adventureInfo;

        for(uint256 i = 0; i < _inputItems.length; i++) {
            require(_inputItems[i].itemOptions.length > 0, "Adventure: Bad array lengths");

            for(uint256 j = 0; j < _inputItems[i].itemOptions.length; j++) {

                uint256 _itemId = _inputItems[i].itemOptions[j].itemId;

                nameToInputIndexToInputInfo[_name][i].itemIds.add(_itemId);
                nameToInputIndexToInputInfo[_name][i].itemIdToQuantity[_itemId] = _inputItems[i].itemOptions[j].quantity;
                nameToInputIndexToInputInfo[_name][i].itemIdToTimeReduction[_itemId] = _inputItems[i].itemOptions[j].timeReduction;
                nameToInputIndexToInputInfo[_name][i].itemIdToBugzReduction[_itemId] = _inputItems[i].itemOptions[j].bugzReduction;
                nameToInputIndexToInputInfo[_name][i].itemIdToChanceOfSuccessChange[_itemId] = _inputItems[i].itemOptions[j].chanceOfSuccessChange;
            }
        }

        emit AdventureAdded(_name, _adventureInfo, _inputItems);
    }

    function isKnownAdventure(string calldata _name) public view returns(bool) {
        return nameToAdventureInfo[_name].adventureStart != 0;
    }
}
