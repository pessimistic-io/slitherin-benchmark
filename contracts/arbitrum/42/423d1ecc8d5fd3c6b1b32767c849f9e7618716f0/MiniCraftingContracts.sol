//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./MiniCraftingState.sol";

abstract contract MiniCraftingContracts is Initializable, MiniCraftingState {

    function __MiniCraftingContracts_init() internal initializer {
        MiniCraftingState.__MiniCraftingState_init();
    }

    function setContracts(
        address _craftingAddress,
        address _legionAddress,
        address _legionMetadataStoreAddress,
        address _treasureAddress,
        address _treasureMetadataStoreAddress,
        address _treasureFragmentAddress,
        address _magicAddress,
        address _consumableAddress,
        address _treasuryAddress,
        address _recruitLevelAddress)
    external onlyAdminOrOwner
    {
        crafting = ICrafting(_craftingAddress);
        legion = ILegion(_legionAddress);
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
        treasure = ITreasure(_treasureAddress);
        treasureMetadataStore = ITreasureMetadataStore(_treasureMetadataStoreAddress);
        treasureFragment = ITreasureFragment(_treasureFragmentAddress);
        magic = IMagic(_magicAddress);
        consumable = IConsumable(_consumableAddress);
        treasury = ITreasury(_treasuryAddress);
        recruitLevel = IRecruitLevel(_recruitLevelAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "MiniCrafting: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(crafting) != address(0)
            && address(legion) != address(0)
            && address(legionMetadataStore) != address(0)
            && address(treasure) != address(0)
            && address(treasureMetadataStore) != address(0)
            && address(treasureFragment) != address(0)
            && address(magic) != address(0)
            && address(consumable) != address(0)
            && address(treasury) != address(0)
            && address(recruitLevel) != address(0);
    }
}
