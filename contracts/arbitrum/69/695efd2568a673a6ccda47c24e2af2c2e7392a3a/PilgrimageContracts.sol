//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./PilgrimageState.sol";

abstract contract PilgrimageContracts is Initializable, PilgrimageState {

    function __PilgrimageContracts_init() internal initializer {
        PilgrimageState.__PilgrimageState_init();
    }

    function setContracts(
        address _randomizerAddress,
        address _legionAddress,
        address _legionMetadataStoreAddress,
        address _legion1155Address,
        address _legionGensis1155Address,
        address _starlightTempleAddress)
    external onlyAdminOrOwner
    {
        randomizer = IRandomizer(_randomizerAddress);
        legion = ILegion(_legionAddress);
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
        legion1155 = ILegion1155(_legion1155Address);
        legionGenesis1155 = ILegion1155(_legionGensis1155Address);
        starlightTemple = IStarlightTemple(_starlightTempleAddress);
    }

    modifier contractsAreSet() {
        require(address(randomizer) != address(0)
            && address(legion) != address(0)
            && address(legion1155) != address(0)
            && address(legionGenesis1155) != address(0)
            && address(starlightTemple) != address(0)
            && address(legionMetadataStore) != address(0), "Contracts aren't set");

        _;
    }
}
