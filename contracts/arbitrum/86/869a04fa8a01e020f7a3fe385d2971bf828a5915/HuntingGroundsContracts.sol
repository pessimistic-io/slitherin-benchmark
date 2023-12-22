//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./HuntingGroundsState.sol";

abstract contract HuntingGroundsContracts is Initializable, HuntingGroundsState {

    function __HuntingGroundsContracts_init() internal initializer {
        HuntingGroundsState.__HuntingGroundsState_init();
    }

    function setContracts(
        address _worldAddress,
        address _bugzAddress,
        address _badgezAddress)
    external
    onlyAdminOrOwner
    {
        world = IWorld(_worldAddress);
        bugz = IBugz(_bugzAddress);
        badgez = IBadgez(_badgezAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "HuntingGrounds: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(world) != address(0)
            && address(bugz) != address(0)
            && address(badgez) != address(0);
    }
}
