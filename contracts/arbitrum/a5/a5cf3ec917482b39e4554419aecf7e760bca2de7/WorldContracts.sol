//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./WorldState.sol";

abstract contract WorldContracts is Initializable, WorldState {

    function __WorldContracts_init() internal initializer {
        WorldState.__WorldState_init();
    }

    function setContracts(
        address _toadzAddress,
        address _huntingGroundsAddress,
        address _craftingAddress)
    external onlyAdminOrOwner
    {
        toadz = IToadz(_toadzAddress);
        huntingGrounds = IHuntingGrounds(_huntingGroundsAddress);
        crafting = ICrafting(_craftingAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "World: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(toadz) != address(0)
            && address(huntingGrounds) != address(0)
            && address(crafting) != address(0);
    }
}
