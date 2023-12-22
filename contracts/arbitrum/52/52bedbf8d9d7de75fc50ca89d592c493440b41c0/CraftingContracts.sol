//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Initializable.sol";

import "./CraftingState.sol";

abstract contract CraftingContracts is Initializable, CraftingState {

    function __CraftingContracts_init() internal initializer {
        CraftingState.__CraftingState_init();
    }

    function setContracts(
        address _bugzAddress,
        address _itemzAddress,
        address _randomizerAddress,
        address _toadzAddress,
        address _worldAddress,
        address _badgezAddress)
    external
    onlyAdminOrOwner
    {
        bugz = IBugz(_bugzAddress);
        itemz = IItemz(_itemzAddress);
        randomizer = IRandomizer(_randomizerAddress);
        toadz = IToadz(_toadzAddress);
        world = IWorld(_worldAddress);
        badgez = IBadgez(_badgezAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Contracts aren't set");
        _;
    }

    modifier worldIsCaller() {
        require(msg.sender == address(world), "Must be called by world");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(bugz) != address(0)
            && address(itemz) != address(0)
            && address(randomizer) != address(0)
            && address(toadz) != address(0)
            && address(world) != address(0)
            && address(badgez) != address(0);
    }
}
