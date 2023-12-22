//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./BalancerCrystalState.sol";

abstract contract BalancerCrystalContracts is Initializable, BalancerCrystalState {

    function __BalancerCrystalContracts_init() internal initializer {
        BalancerCrystalState.__BalancerCrystalState_init();
    }
}
