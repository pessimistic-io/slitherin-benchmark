//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./TreasureTriadState.sol";

abstract contract TreasureTriadContracts is Initializable, TreasureTriadState {

    function __TreasureTriadContracts_init() internal initializer {
        TreasureTriadState.__TreasureTriadState_init();
    }

    function setContracts(
        address _advancedQuestingAddress,
        address _treasureMetadataStoreAddress,
        address _randomizerAddress)
    external onlyAdminOrOwner
    {
        advancedQuesting = IAdvancedQuesting(_advancedQuestingAddress);
        treasureMetadataStore = ITreasureMetadataStore(_treasureMetadataStoreAddress);
        randomizer = IRandomizer(_randomizerAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "TreasureTriad: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(advancedQuesting) != address(0)
            && address(treasureMetadataStore) != address(0)
            && address(randomizer) != address(0);
    }
}
