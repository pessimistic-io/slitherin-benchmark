//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./AdvancedQuestingState.sol";

abstract contract AdvancedQuestingContracts is Initializable, AdvancedQuestingState {

    function __AdvancedQuestingContracts_init() internal initializer {
        AdvancedQuestingState.__AdvancedQuestingState_init();
    }

    function setContracts(
        address _randomizerAddress,
        address _questingAddress,
        address _legionAddress,
        address _legionMetadataStoreAddress,
        address _treasureAddress,
        address _consumableAddress,
        address _treasureMetadataStoreAddress,
        address _treasureTriadAddress,
        address _treasureFragmentAddress)
    external onlyAdminOrOwner
    {
        randomizer = IRandomizer(_randomizerAddress);
        questing = IQuesting(_questingAddress);
        legion = ILegion(_legionAddress);
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
        treasure = ITreasure(_treasureAddress);
        consumable = IConsumable(_consumableAddress);
        treasureMetadataStore = ITreasureMetadataStore(_treasureMetadataStoreAddress);
        treasureTriad = ITreasureTriad(_treasureTriadAddress);
        treasureFragment = ITreasureFragment(_treasureFragmentAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(randomizer) != address(0)
            && address(questing) != address(0)
            && address(legion) != address(0)
            && address(legionMetadataStore) != address(0)
            && address(treasure) != address(0)
            && address(consumable) != address(0)
            && address(treasureMetadataStore) != address(0)
            && address(treasureTriad) != address(0)
            && address(treasureFragment) != address(0);
    }
}
