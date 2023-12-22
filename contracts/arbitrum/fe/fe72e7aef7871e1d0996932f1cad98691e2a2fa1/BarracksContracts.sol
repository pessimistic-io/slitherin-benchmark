//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./BarracksState.sol";

abstract contract BarracksContracts is Initializable, BarracksState {

    function __BarracksContracts_init() internal initializer {
        BarracksState.__BarracksState_init();
    }

    function setContracts(
        address _randomizerAddress,
        address _magicAddress,
        address _legionAddress,
        address _legionMetadataStoreAddress,
        address _treasuryAddress)
    external onlyAdminOrOwner
    {
        randomizer = IRandomizer(_randomizerAddress);
        magic = IMagic(_magicAddress);
        legion = ILegion(_legionAddress);
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
        treasury = ITreasury(_treasuryAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Barracks: Contracts aren't set");

        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(randomizer) != address(0)
            && address(magic) != address(0)
            && address(legionMetadataStore) != address(0)
            && address(treasury) != address(0)
            && address(legion) != address(0);
    }
}
