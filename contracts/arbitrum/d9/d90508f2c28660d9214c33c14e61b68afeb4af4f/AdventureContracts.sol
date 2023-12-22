//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./AdventureState.sol";

abstract contract AdventureContracts is Initializable, AdventureState {

    function __AdventureContracts_init() internal initializer {
        AdventureState.__AdventureState_init();
    }

    function setContracts(
        address _randomizerAddress,
        address _itemzAddress,
        address _bugzAddress,
        address _badgezAddress,
        address _worldAddress)
    external onlyAdminOrOwner
    {
        randomizer = IRandomizer(_randomizerAddress);
        itemz = IItemz(_itemzAddress);
        bugz = IBugz(_bugzAddress);
        badgez = IBadgez(_badgezAddress);
        world = IWorld(_worldAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Adventure: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(randomizer) != address(0)
            && address(itemz) != address(0)
            && address(bugz) != address(0)
            && address(badgez) != address(0)
            && address(world) != address(0);
    }
}
