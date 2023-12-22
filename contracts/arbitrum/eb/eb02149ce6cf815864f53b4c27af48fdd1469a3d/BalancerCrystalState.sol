//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC1155Upgradeable.sol";

import "./IBalancerCrystal.sol";
import "./AdminableUpgradeable.sol";

abstract contract BalancerCrystalState is Initializable, IBalancerCrystal, ERC1155Upgradeable, AdminableUpgradeable {

    function __BalancerCrystalState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC1155Upgradeable.__ERC1155_init("");
    }
}
