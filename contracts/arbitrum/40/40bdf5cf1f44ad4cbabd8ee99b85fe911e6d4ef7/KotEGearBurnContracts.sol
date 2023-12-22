//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./KotEGearBurnState.sol";

abstract contract KotEGearBurnContracts is Initializable, KotEGearBurnState {

    function __KotEGearBurnContracts_init() internal initializer {
        KotEGearBurnState.__KotEGearBurnState_init();
    }

    function setContracts(
        address _knightGearAddress,
        address _consumableAddress)
    external onlyAdminOrOwner
    {
        knightGear = IKotEKnightGear(_knightGearAddress);
        consumable = IConsumable(_consumableAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "KotEGearBurn: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(knightGear) != address(0)
            && address(consumable) != address(0);
    }
}
