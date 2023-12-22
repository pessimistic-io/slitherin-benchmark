//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./StarlightTempleState.sol";

abstract contract StarlightTempleContracts is Initializable, StarlightTempleState {

    function __StarlightTempleContracts_init() internal initializer {
        StarlightTempleState.__StarlightTempleState_init();
    }

    function setContracts(
        address _randomizerAddress,
        address _legionMetadataStoreAddress,
        address _consumableAddress,
        address _legionAddress,
        address _treasuryAddress)
    external onlyAdminOrOwner
    {
        randomizer = IRandomizer(_randomizerAddress);
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
        consumable = IConsumable(_consumableAddress);
        legion = ILegion(_legionAddress);
        treasury = ITreasury(_treasuryAddress);
    }

    modifier contractsAreSet() {
        require(address(randomizer) != address(0)
            && address(consumable) != address(0)
            && address(legion) != address(0)
            && address(treasury) != address(0)
            && address(legionMetadataStore) != address(0), "Contracts aren't set");

        _;
    }
}
