//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./TreasureCorruptionHandlerState.sol";

abstract contract TreasureCorruptionHandlerContracts is Initializable, TreasureCorruptionHandlerState {

    function __TreasureCorruptionHandlerContracts_init() internal initializer {
        TreasureCorruptionHandlerState.__TreasureCorruptionHandlerState_init();
    }

    function setContracts(
        address _corruptionRemovalAddress,
        address _treasureAddress,
        address _treasureMetadataStoreAddress,
        address _consumableAddress,
        address _treasuryAddress)
    external onlyAdminOrOwner
    {
        corruptionRemoval = ICorruptionRemoval(_corruptionRemovalAddress);
        treasure = ITreasure(_treasureAddress);
        treasureMetadataStore = ITreasureMetadataStore(_treasureMetadataStoreAddress);
        consumable = IConsumable(_consumableAddress);
        treasuryAddress = _treasuryAddress;
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "TreasureCorruptionHandler: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(corruptionRemoval) != address(0)
            && address(treasure) != address(0)
            && address(treasureMetadataStore) != address(0)
            && address(consumable) != address(0)
            && treasuryAddress != address(0);
    }
}
