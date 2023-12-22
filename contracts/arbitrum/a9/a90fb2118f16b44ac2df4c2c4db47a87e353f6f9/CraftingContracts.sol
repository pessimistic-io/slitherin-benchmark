//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./CraftingState.sol";

abstract contract CraftingContracts is Initializable, CraftingState {

    function __CraftingContracts_init() internal initializer {
        CraftingState.__CraftingState_init();
    }

    function setContracts(
        address _randomizerAddress,
        address _treasureAddress,
        address _legionAddress,
        address _treasureMetadataStoreAddress,
        address _legionMetadataStoreAddress,
        address _magicAddress,
        address _treasuryAddress,
        address _consumableAddress)
    external onlyAdminOrOwner
    {
        consumable = IConsumable(_consumableAddress);
        randomizer = IRandomizer(_randomizerAddress);
        treasure = ITreasure(_treasureAddress);
        legion = ILegion(_legionAddress);
        treasureMetadataStore = ITreasureMetadataStore(_treasureMetadataStoreAddress);
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
        magic = IMagic(_magicAddress);
        treasury = ITreasury(_treasuryAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Crafting: Contracts aren't set");

        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(randomizer) != address(0)
            && address(treasure) != address(0)
            && address(legion) != address(0)
            && address(treasureMetadataStore) != address(0)
            && address(legionMetadataStore) != address(0)
            && address(treasury) != address(0)
            && address(consumable) != address(0)
            && address(magic) != address(0);
    }
}
