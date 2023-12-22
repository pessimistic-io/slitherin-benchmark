//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./CraftingDiamondState.sol";

abstract contract CraftingDiamondContracts is Initializable, CraftingDiamondState {

    function __CraftingDiamondContracts_init() internal initializer {
        CraftingDiamondState.__CraftingDiamondState_init();
    }

    function setContracts(
        address _randomizerAddress,
        address _treasureAddress,
        address _legionAddress,
        address _treasureMetadataStoreAddress,
        address _legionMetadataStoreAddress,
        address _magicAddress,
        address _treasuryAddress,
        address _consumableAddress,
        address _corruptionAddress)
    external onlyAdminOrOwner
    {
        randomizer = IRandomizer(_randomizerAddress);
        treasure = ITreasure(_treasureAddress);
        legion = ILegion(_legionAddress);
        treasureMetadataStore = ITreasureMetadataStore(_treasureMetadataStoreAddress);
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
        magic = IMagic(_magicAddress);
        treasury = ITreasury(_treasuryAddress);
        consumable = IConsumable(_consumableAddress);
        corruption = ICorruption(_corruptionAddress);
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
            && address(magic) != address(0)
            && address(corruption) != address(0);
    }
}
