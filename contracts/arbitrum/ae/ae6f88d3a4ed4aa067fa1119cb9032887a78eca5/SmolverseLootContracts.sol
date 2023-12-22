//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "./Initializable.sol";

import {SmolverseLootState} from "./SmolverseLootState.sol";

abstract contract SmolverseLootContracts is Initializable, SmolverseLootState {
    function __SmolverseLootContracts_init() internal initializer {
        SmolverseLootState.__SmolverseLootState_init();
    }

    function setContracts(
        address _smolCarsAddress,
        address _swolercyclesAddress,
        address _treasuresAddress,
        address _magicAddress,
        address _smolChopShopAddress,
        address _troveAddress,
        address _smolPetsAddress,
        address _swolPetsAddress,
        address _smolBrainsAddress,
        address _smolsStateAddress
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        smolCarsAddress = _smolCarsAddress;
        swolercyclesAddress = _swolercyclesAddress;
        treasuresAddress = _treasuresAddress;
        magicAddress = _magicAddress;
        smolChopShopAddress = _smolChopShopAddress;
        troveAddress = _troveAddress;
        smolPetsAddress = _smolPetsAddress;
        swolPetsAddress = _swolPetsAddress;
        smolBrainsAddress = _smolBrainsAddress;
        smolsStateAddress = _smolsStateAddress;
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns (bool) {
        return
            smolCarsAddress != address(0) &&
            swolercyclesAddress != address(0) &&
            treasuresAddress != address(0) &&
            magicAddress != address(0) &&
            smolChopShopAddress != address(0) &&
            troveAddress != address(0) &&
            smolPetsAddress != address(0) &&
            swolPetsAddress != address(0) &&
            smolBrainsAddress != address(0) &&
            smolsStateAddress != address(0);
    }
}

