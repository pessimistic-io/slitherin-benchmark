//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./WartlocksHallowState.sol";

abstract contract WartlocksHallowContracts is Initializable, WartlocksHallowState {

    function __WartlocksHallowContracts_init() internal initializer {
        WartlocksHallowState.__WartlocksHallowState_init();
    }

    function setContracts(
        address _magicStakingAddress,
        address _worldAddress,
        address _badgezAddress,
        address _itemzAddress,
        address _bugzAddress)
    external
    onlyAdminOrOwner
    {
        magicStaking = IMagicStaking(_magicStakingAddress);
        world = IWorld(_worldAddress);
        badgez = IBadgez(_badgezAddress);
        itemz = IItemz(_itemzAddress);
        bugz = IBugz(_bugzAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(magicStaking) != address(0)
            && address(world) != address(0)
            && address(badgez) != address(0)
            && address(itemz) != address(0)
            && address(bugz) != address(0);
    }
}
