//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./IRandomizer.sol";
import "./AdminableUpgradeable.sol";
import "./IToadz.sol";
import "./IWorld.sol";

abstract contract ToadzBalanceState is Initializable, AdminableUpgradeable {

    IToadz public toadz;
    IWorld public world;

    function __ToadzBalanceState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
    }
}
