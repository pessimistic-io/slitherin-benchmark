//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./IBadgez.sol";
import "./ERC1155OnChainBaseUpgradeable.sol";
import "./AdminableUpgradeable.sol";

abstract contract BadgezState is Initializable, IBadgez, ERC1155OnChainBaseUpgradeable {

    function __BadgezState_init() internal initializer {
        ERC1155OnChainBaseUpgradeable.__ERC1155OnChainBase_init();
    }
}
