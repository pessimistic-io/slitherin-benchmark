//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./SummoningState.sol";

abstract contract SummoningContracts is Initializable, SummoningState {

    function __SummoningContracts_init() internal initializer {
        SummoningState.__SummoningState_init();
    }

    function setContracts(
        address _legionAddress,
        address _legionMetadataStoreAddress,
        address _randomizerAddress,
        address _magicAddress,
        address _treasuryAddress,
        address _consumableAddress,
        address _craftingAddress,
        address _balancerCrystal)
    external onlyAdminOrOwner
    {
        randomizer = IRandomizer(_randomizerAddress);
        legion = ILegion(_legionAddress);
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
        magic = IMagic(_magicAddress);
        treasury = ITreasury(_treasuryAddress);
        consumable = IConsumable(_consumableAddress);
        crafting = ICrafting(_craftingAddress);
        balancerCrystal = IERC1155Upgradeable(_balancerCrystal);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Summoning: Contracts aren't set");

        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(randomizer) != address(0)
            && address(legion) != address(0)
            && address(magic) != address(0)
            && address(treasury) != address(0)
            && address(consumable) != address(0)
            && address(legionMetadataStore) != address(0)
            && address(crafting) != address(0)
            && address(balancerCrystal) != address(0);
    }
}
