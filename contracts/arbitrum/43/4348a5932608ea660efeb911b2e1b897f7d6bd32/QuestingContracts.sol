//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./QuestingState.sol";

abstract contract QuestingContracts is Initializable, QuestingState {

    function __QuestingContracts_init() internal initializer {
        QuestingState.__QuestingState_init();
    }

    function setContracts(
        address _randomizerAddress,
        address _treasureAddress,
        address _legionAddress,
        address _treasureMetadataStoreAddress,
        address _legionMetadataStoreAddress,
        address _lpAddress,
        address _consumableAddress,
        address _treasuryAddress)
    external onlyAdminOrOwner
    {
        randomizer = IRandomizer(_randomizerAddress);
        treasure = ITreasure(_treasureAddress);
        legion = ILegion(_legionAddress);
        treasureMetadataStore = ITreasureMetadataStore(_treasureMetadataStoreAddress);
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
        lp = ILP(_lpAddress);
        consumable = IConsumable(_consumableAddress);
        treasury = ITreasury(_treasuryAddress);
    }

    modifier contractsAreSet() {
        require(address(randomizer) != address(0)
            && address(treasure) != address(0)
            && address(legion) != address(0)
            && address(treasureMetadataStore) != address(0)
            && address(legionMetadataStore) != address(0)
            && address(consumable) != address(0)
            && address(treasury) != address(0)
            && address(lp) != address(0), "Contracts aren't set");

        _;
    }
}
