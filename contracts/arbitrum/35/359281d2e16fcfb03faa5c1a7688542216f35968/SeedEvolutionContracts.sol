//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./SeedEvolutionState.sol";

abstract contract SeedEvolutionContracts is Initializable, SeedEvolutionState {

    function __SeedEvolutionContracts_init() internal initializer {
        SeedEvolutionState.__SeedEvolutionState_init();
    }

    function setContracts(
        address _randomizerAddress,
        address _seedOfLifeAddress,
        address _balancerCrystalAddress,
        address _magicAddress,
        address _treasuryAddress,
        address _imbuedSoulAddress,
        address _treasureMetadataStoreAddress,
        address _treasureAddress,
        address _solItemAddress)
    external
    onlyAdminOrOwner
    {
        randomizer = IRandomizer(_randomizerAddress);
        seedOfLife = ISeedOfLife(_seedOfLifeAddress);
        balancerCrystal = IBalancerCrystal(_balancerCrystalAddress);
        magic = IMagic(_magicAddress);
        treasuryAddress = _treasuryAddress;
        imbuedSoul = IImbuedSoul(_imbuedSoulAddress);
        treasureMetadataStore = ITreasureMetadataStore(_treasureMetadataStoreAddress);
        treasure = ITreasure(_treasureAddress);
        solItem = ISoLItem(_solItemAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(randomizer) != address(0)
            && address(seedOfLife) != address(0)
            && address(balancerCrystal) != address(0)
            && address(magic) != address(0)
            && treasuryAddress != address(0)
            && address(imbuedSoul) != address(0)
            && address(treasureMetadataStore) != address(0)
            && address(treasure) != address(0)
            && address(solItem) != address(0);
    }
}
